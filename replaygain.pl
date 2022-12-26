#!/usr/bin/perl

# This script is meant to manage a FLAC music library, specifically the
# tags.

# This script will:

# * Remove empty tags and duplicate tag fields
# * Remove leading and trailing whitespace from tags
# * Check FLAC version and re-encode (-8) if an older version than:
# $flac_version[1] (the installed version of 'flac')
# * Remove ID3v2 tags while re-encoding, but keep VorbisComment tags
# * Remove tags (only RATING as of right now)
# * Add DISCNUMBER, ALBUMARTIST, TOTALTRACKS tags
# * Remove leading 0s from the TRACKNUMBER, TOTALTRACKS, TRACKTOTAL,
# DISCNUMBER, TOTALDISCS, DISCTOTAL tags
# * Remove album art (right now that subroutine is disabled)
# * Add ReplayGain tags for all albums, unless they already exist
# * Sort tag fields alphabetically and uppercase them before writing
# * Rename and re-organize files based on the tags
# * Remove empty sub-directories under the FLAC library directory

# This is the directory structure, and file name, used / created by the
# script:
# ${library}/${albumartist}/${album}/${discnumber}-${tracknumber}.
# ${title}.flac

# I haven't tried running the script in a directory that has FLAC albums
# as a single file. It will probably not work as expected. Though, it's
# easy to separate a single file FLAC album into separate tracks if you
# have the CUE file. I only keep my FLAC albums as separate files per
# track. I just think it's good practice.

# After running a FLAC library through this script, it will be easier to
# match albums against the MusicBrainz database, in case you want to use
# MusicBrainz Picard.

use v5.34;
use strict;
use warnings;
use File::Copy qw(move);
use File::Basename qw(basename dirname);
use File::Path qw(make_path);
use Cwd qw(abs_path);

my(%regex, %tags_if, %tags_of, %files, @dirs, $library, $depth_og);
my($discnumber_ref, $totaldiscs_ref, $disctotal_ref);
my($artist_ref, $albumartist_ref, $album_ref, $title_ref);
my($tracknumber_ref, $totaltracks_ref, $tracktotal_ref);

$regex{quote} = qr/^(\")|(\")$/;
$regex{space} = qr/(^\s*)|(\s*$)/;
$regex{zero} = qr/^0+([0-9]+)$/;
$regex{fraction} = qr/^([0-9]+)\s*\/\s*([0-9]+)$/;
$regex{tag} = qr/^([^=]+)=(.*)$/;
$regex{disc} = qr/\s*[[:punct:]]?(cd|disc)\s*([0-9]+)(\s*of\s*([0-9]+))?[[:punct:]]?\s*$/i;
$regex{id3v2} = qr/has an ID3v2 tag/;

# Check if the necessary commands are installed to test FLAC files.
chomp(my @flac_req = (`command -v flac metaflac`));

if (scalar(@flac_req) != 2) {
	say "\n" . 'This script needs \'flac\' and \'metaflac\' installed!' . "\n";
	exit
}

# Check the installed version of 'flac'.
my @flac_version = split(' ', `flac --version`);

if (scalar(@ARGV) != 1 or ! -d $ARGV[0]) { usage(); }

$library = abs_path($ARGV[0]);
$depth_og = scalar(split('/', $library));

# Find all the sub-directories under the FLAC library directory.
getdirs();

# This is the main loop of the script, it calls most of the subroutines.
foreach my $dn (@dirs) {
	getfiles($dn);

	foreach my $fn (sort(keys(%{$files{flac}}))) {
		mk_refs($fn);
		existstag($fn, 'artist', 'album', 'tracknumber', 'title');
		vendor($fn);
		rm_tag($fn, 'rating');
		discnumber($fn, $dn);
		albumartist($fn);
# rm_albumart($fn);
		changed($fn);
		writetags($fn, 1);
	}
}

# Running this loop after the first loop, because it renames the FLAC
# files.
foreach my $dn (@dirs) {
	getfiles($dn);

	foreach my $fn (sort(keys(%{$files{flac}}))) {
		mk_refs($fn);
		tags2fn($fn);
	}
}

# Remove all the empty sub-directories in the FLAC library directory,
# since files may have been moved by the 'tags2fn' subroutine.
rm_empty_dirs();

# Find all the sub-directories under the FLAC library directory. We're
# checking the sub-directories a second time, because they may have
# changed due to the 'tags2fn' subroutine being run.
getdirs();

# Adding the TOTALTRACKS tag last, because we need to do that after the
# files have been moved to the proper directories. The same rule applies
# to the ReplayGain tags.
foreach my $dn (@dirs) {
	getfiles($dn);

	replaygain($dn);

	foreach my $fn (sort(keys(%{$files{flac}}))) {
		mk_refs($fn);
		totaltracks($fn);
		rm_zeropad($fn);
		changed($fn);
		writetags($fn, 1);
	}
}

# The 'usage' subroutine prints syntax, and then quits.
sub usage {
	say "\n" . 'Usage: ' . basename($0) . ' [FLAC library directory]' . "\n";
	exit;
}

# The 'or_warn' subroutine shows a warning message if the previous shell
# command failed. system() calls seems to follow different rules than
# the other calls, hence this subroutine is necessary for those
# situations.
sub or_warn {
	my $msg = "\n" . shift;

	if ($? != 0) { warn $msg; }
}

# The 'getdirs' subroutine finds all the sub-directories under the FLAC
# library directory. The list of directories is sorted with the deepest
# directories first.
sub getdirs {
	my(@lines, @dirs_tmp, @path_parts, $depth_tmp, $depth_max);
	$depth_max = 0;

	undef(@dirs);

	open(my $find, '-|', 'find', $library, '-type', 'd', '-nowarn')
	or die "Can't open 'find': $!";
	chomp(@lines = (<$find>));
	close($find) or die "Can't close 'find': $!";

	foreach my $fn (@lines) {
		@path_parts = split('/', $fn);
		$depth_tmp = scalar(@path_parts);

		if ($depth_tmp > $depth_max) {
			$depth_max = $depth_tmp;
		}
	}

	for (my $i = $depth_max; $i > $depth_og; $i--) {
		foreach my $fn (@lines) {
			@path_parts = split('/', $fn);
			$depth_tmp = scalar(@path_parts);

			if ($depth_tmp == $i) {
				push(@dirs_tmp, $fn);
			}
		}

		push(@dirs, sort(@dirs_tmp));
		undef(@dirs_tmp);
	}

	push(@dirs, $library);
}

# The 'getfiles' subroutine gets a list of FLAC files in the directory
# passed to it.
sub getfiles {
	my $dn = shift;

	my(@lines);

	undef(%files);
	undef(%tags_if);
	undef(%tags_of);

	open(my $find, '-|', 'find', $dn, '-mindepth', '1', '-maxdepth', '1', '-type', 'f', '-nowarn')
	or die "Can't open 'find': $!";
	chomp(@lines = (<$find>));
	close($find) or die "Can't close 'find': $!";

	foreach my $fn (@lines) {
		if ($fn =~ m/\.flac$/i) {
			$files{flac}{$fn} = { gettags($fn) };
		} else {
			$files{other}{$fn} = ();
		}
	}

	foreach my $fn (keys(%{$files{flac}})) {
		my $tags_ref = \$files{flac}{$fn};

		foreach my $field (keys(%{$$tags_ref})) {
			$tags_if{$fn}{$field} = $$tags_ref->{$field}[0];
			$tags_of{$fn}{$field} = $$tags_ref->{$field}[0];
		}
	}
}

# The 'gettags' subroutine reads the tags from a FLAC file.
sub gettags {
	my $fn = shift;

	my(%alltags, @lines);

	open(my $output, '-|', 'metaflac', '--no-utf8-convert', '--show-vendor-tag', '--export-tags-to=-', $fn)
	or die "Can't open 'metaflac': $!";
	chomp(@lines = (<$output>));
	close($output) or die "Can't close 'metaflac': $!";

	while (my $line = shift(@lines)) {
		my(@tag, $field, $value);

		$line =~ s/$regex{quote}//g;

		if ($line =~ m/^reference/) {
			@tag = split(' ', $line);
			$field = 'vendor_ref';

			if (length($tag[2])) { $value = $tag[2]; }
			else {
				undef(@tag);
				$value = $line;
			}
		}

		if ($line =~ m/$regex{tag}/) {
			$field = lc($1);
			$value = $2;

			$field =~ s/$regex{space}//;
			$value =~ s/$regex{space}//;
		}

		if (! length($field) or ! length($value)) { next; }

		push(@{$alltags{$field}}, $value);
	}

	return(%alltags);
}

# The 'mk_refs' subroutine creates references for other subroutines to
# have easier access to tags.
sub mk_refs {
	my $fn = shift;

	$discnumber_ref = \$tags_of{$fn}{discnumber};
	$totaldiscs_ref = \$tags_of{$fn}{totaldiscs};
	$disctotal_ref = \$tags_of{$fn}{disctotal};
	$tracknumber_ref = \$tags_of{$fn}{tracknumber};
	$totaltracks_ref = \$tags_of{$fn}{totaltracks};
	$tracktotal_ref = \$tags_of{$fn}{tracktotal};
	$artist_ref = \$tags_of{$fn}{artist};
	$albumartist_ref = \$tags_of{$fn}{albumartist};
	$album_ref = \$tags_of{$fn}{album};
	$title_ref = \$tags_of{$fn}{title};
}

# The 'existstag' subroutine checks for the existence of the chosen tags
# passed to it. If it doesn't find the tag, it quits.
sub existstag {
	my $fn = shift;

	while (my $field = shift(@_)) {
		if (! length($tags_of{$fn}{$field})) {
			say $fn . ': doesn\'t have ' . $field . ' tag';
			exit;
		}
	}
}

# The 'vendor' subroutine re-encodes the FLAC file, if it was encoded
# with an old version of FLAC. If the FLAC has ID3v2 tags, they will be
# removed in the process of decoding the FLAC to WAV, before re-encoding
# it.
sub vendor {
	my $fn = shift;

	my($newfn, $newfn_flac, $newfn_wav, $newfn_stderr, $newfn_art);
	my $has_id3v2 = 0;

	my $vendor_ref = \$tags_of{$fn}{vendor_ref};

	sub sigint {
		say "Interrupted by user!";

		while (my $fn = shift(@_)) {
			if (-f $fn) {
				unlink($fn) or die "Can't remove '$fn': $!";
			}
		}

		exit;
	}

	unless (! length($$vendor_ref) or $$vendor_ref ne $flac_version[1]) {
		return();
	}

	$newfn = $fn;
	$newfn =~ s/\.[^.]*$//;
	$newfn = $newfn . '-' . int(rand(10000));
	$newfn_flac = $newfn . '.flac';
	$newfn_wav = $newfn . '.wav';
	$newfn_art = $newfn . '.albumart';
	$newfn_stderr = $newfn . '.stderr';

	print $fn . ': old encoder (' . $$vendor_ref . '), re-encoding... ';

# Duplicate STDERR (for restoration later).
# Redirect STDERR to a file ($newfn_stderr).
	open(my $stderr_dup, ">&STDERR") or die "Can't dup STDERR: $!";
	close(STDERR) or die "Can't close STDERR: $!";
	open(STDERR, '>', $newfn_stderr) or die "Can't open '$newfn_stderr': $!";

	system('flac', '--silent', '-8', $fn, "--output-name=$newfn_flac");
	or_warn("Can't encode file");

# Close the STDERR file ($newfn_stderr).
# Restore STDERR from $stderr_dup.
# Close the $stderr_dup filehandle.
	close(STDERR) or die "Can't close STDERR: $!";
	open(STDERR, ">&", $stderr_dup) or die "Can't dup STDERR: $!";
	close($stderr_dup) or die "Can't close STDERR: $!";

	given ($?) {
		when (0) {
			move($newfn_flac, $fn) or die "Can't rename '$newfn_flac': $!";
			say 'done';
		}
		when (2) {
			sigint($newfn_flac, $newfn_stderr);
		}
		default {
# Open a filehandle that reads from the STDERR file ($newfn_stderr).
# Checks if FLAC file has ID3v2 tags.
			open(my $stderr_fh, '<', $newfn_stderr)
			or die "Can't open '$newfn_stderr': $!";
			while (chomp(my $line = <$stderr_fh>)) {
				if ($line =~ m/$regex{id3v2}/) {
					$has_id3v2 = 1;
					last;
				}
			}
			close($stderr_fh) or die "Can't close '$newfn_stderr': $!";

			if ($has_id3v2) {
				print "\n" . $fn . ': ' . 'replacing ID3v2 tags with VorbisComment... ';

# Decode the FLAC file to WAV (in order to lose the ID3v2 tags).
				system('flac', '--silent', '--decode', $fn, "--output-name=$newfn_wav");
				or_warn("Can't decode file");

				if ($? == 2) { sigint($newfn_wav, $newfn_stderr); }

# Back up the album art, if it exists.
				system("metaflac --export-picture-to=\"$newfn_art\" \"$fn\" 1>&- 2>&-");

# Encode the WAV file to FLAC.
				if (-f $newfn_art) {
					system('flac', '--silent', '-8', "--picture=$newfn_art", $newfn_wav, "--output-name=$newfn_flac");
					or_warn("Can't encode file");

					unlink($newfn_art)
					or die "Can't remove '$newfn_art': $!";
				} else {
					system('flac', '--silent', '-8', $newfn_wav, "--output-name=$newfn_flac");
					or_warn("Can't encode file");
				}

				unlink($newfn_wav)
				or die "Can't remove '$newfn_wav': $!";

				if ($? == 0) {
					move($newfn_flac, $fn)
					or die "Can't move '$newfn_flac': $!";
					say 'done';

# Rewrite the tags. They were removed in the decoding process.
					writetags($fn, 0);
				} elsif ($? == 2) {
					sigint($newfn_wav, $newfn_flac, $newfn_stderr);
				}
			}
		}
	}

# Delete the STDERR file.
	unlink($newfn_stderr) or die "Can't remove '$newfn_stderr': $!";
}

# The 'rm_tag' subroutine removes tags of choice.
sub rm_tag {
	my $fn = shift;

	while (my $field = shift(@_)) {
		if (length($tags_of{$fn}{$field})) {
			delete($tags_of{$fn}{$field});
		}
	}
}

# The 'discnumber' subroutine creates the DISCNUMBER tag, if it doesn't
# exist already. DISCTOTAL is also added, if possible. This subroutine
# needs to be run before 'albumartist', and 'totaltracks'.
sub discnumber {
	my $fn = shift;
	my $dn = shift;

	if ($$discnumber_ref =~ m/$regex{fraction}/) {
		$$discnumber_ref = $1;

		if (! lengh($$totaldiscs_ref)) {
			$$totaldiscs_ref = $2;
		}
	}

	if (! length($$discnumber_ref)) {
		if ($$album_ref =~ m/$regex{disc}/) {
			$$discnumber_ref = $2;

			if (! length($$totaldiscs_ref) and length($4)) {
				$$totaldiscs_ref = $4;
			}

			$$album_ref =~ s/$regex{disc}//;
		}
	}

	if (! length($$discnumber_ref)) {
		if ($dn =~ m/$regex{disc}/) {
			$$discnumber_ref = $2;

			if (! length($$totaldiscs_ref) and length($4)) {
				$$totaldiscs_ref = $4;
			}
		} else { $$discnumber_ref = 1; }
	}

	if (! length($$totaldiscs_ref)) {
		if (length($$disctotal_ref)) {
			$$totaldiscs_ref = $$disctotal_ref;
		}
	}
}

# The 'albumartist' subroutine creates the ALBUMARTIST tag, if it
# doesn't exist already.
sub albumartist {
	my $fn = shift;

	my(%tracks, $tracks);

	if (length($$discnumber_ref)) {
		foreach my $fn (keys(%tags_of)) {
			my $discnumber_ref = \$tags_of{$fn}{discnumber};

			if (length($$discnumber_ref)) {
				${tracks}{$$discnumber_ref}++;
			}
		}

		$tracks = ${tracks}{$$discnumber_ref};

		if (! length($$albumartist_ref)) {
			my(%artist, $max);

			if ($tracks == 1) { $max = $tracks; } else { $max = $tracks / 2; }

			foreach my $fn (keys(%tags_of)) {
				my $artist_ref = \$tags_of{$fn}{artist};

				$artist{$$artist_ref} = 1;
			}

			if (keys(%artist) > $max) {
				$$albumartist_ref = 'Various Artists';
			} else { $$albumartist_ref = $$artist_ref; }
		}
	}
}

# The 'rm_albumart' subroutine removes the album art, by removing the
# PICTURE metadata block.
sub rm_albumart {
	my $fn = shift;

	system('metaflac', '--remove', ,'--block-type=PICTURE', $fn);
	or_warn("Can't remove album art");

	say $fn . ': removed album art';
}

# The 'changed' subroutine will print any changes that have been made to
# the tags, by the other subroutines.
sub changed {
	my $fn = shift;

	my(%fields);

# Collect all the tag fields from the input tags.
	foreach my $field (keys(%{$tags_if{$fn}})) {
		$fields{$field} = 1;
	}

# Collect all the tag fields from the output tags. If there's tag fields
# with empty values, ignore those hash elements. They get
# unintentionally created, when using references in other subroutines.
	foreach my $field (keys(%{$tags_of{$fn}})) {
		if (! length($tags_of{$fn}{$field})) { next; }

		$fields{$field} = 1;
	}

	foreach my $field (sort(keys(%fields))) {
		my $tag_if_ref = \$tags_if{$fn}{$field};
		my $tag_of_ref = \$tags_of{$fn}{$field};

		if (! length($$tag_if_ref)) {
			say $fn . ': added ' . $field . ' tag';
			next;
		}

		if (! length($$tag_of_ref)) {
			say $fn . ': removed ' . $field . ' tag';
			next;
		}

		if ($$tag_if_ref ne $$tag_of_ref) {
			say $fn . ': fixed ' . $field . ' tag';
			next;
		}
	}
}

# The 'rm_zeropad' subroutine removes leading 0s from the TRACKNUMBER,
# TOTALTRACKS, TRACKTOTAL, DISCNUMBER, TOTALDISCS, DISCTOTAL tags. This
# subroutine needs to be run after 'discnumber' and 'totaltracks'.
sub rm_zeropad {
	my $fn = shift;

	if (length($$tracknumber_ref)) {
		$$tracknumber_ref =~ s/$regex{zero}/$1/;
	}

	if (length($$totaltracks_ref)) {
		$$totaltracks_ref =~ s/$regex{zero}/$1/;
	}

	if (length($$tracktotal_ref)) {
		$$tracktotal_ref =~ s/$regex{zero}/$1/;
	}

	if (length($$discnumber_ref)) {
		$$discnumber_ref =~ s/$regex{zero}/$1/;
	}

	if (length($$totaldiscs_ref)) {
		$$totaldiscs_ref =~ s/$regex{zero}/$1/;
	}

	if (length($$disctotal_ref)) {
		$$disctotal_ref =~ s/$regex{zero}/$1/;
	}
}

# The 'replaygain' subroutine adds ReplayGain tags, if they don't exist
# already.
sub replaygain {
	my $dn = shift;

	my(%replaygain);

	if (! keys(%{$files{flac}})) {
		return;
	}

	foreach my $fn (keys(%tags_of)) {
		my $replaygain_ref = \$tags_of{$fn}{replaygain_album_gain};

		if (length($$replaygain_ref)) {
			$replaygain{$$replaygain_ref}++;
		}
	}

	if (! keys(%replaygain)) {
		print $dn . ': adding ReplayGain... ';

		system('metaflac', '--remove-replay-gain', keys(%{$files{flac}}));
		or_warn("Can't remove ReplayGain");
		system('metaflac', '--add-replay-gain', keys(%{$files{flac}}));
		or_warn("Can't add ReplayGain");

		if ($? == 0) {
			say 'done';

			getfiles($dn);
		}
	}
}

# The 'writetags' subroutine sorts the tags by field name, and
# uppercases the field names. Then it writes the tags to the FLAC file.
sub writetags {
	my $fn = shift;
	my $is_equal = shift;

	my $tags_if_ref = \$files{flac}{$fn};
	my $tags_of_ref = \$tags_of{$fn};

	my(@mflac_if, @mflac_of);

# Push the input tags to the @mflac_if array.
	foreach my $field (sort(keys(%{$$tags_if_ref}))) {
		for (my $i = 0; $i < scalar(@{$$tags_if_ref->{$field}}); $i++) {
			my $tag_ref = \$$tags_if_ref->{$field}[$i];

			unless ($field eq 'vendor_ref') {
				push(@mflac_if, uc($field) . '=' . $$tag_ref);
			}
		}
	}

# Push the output tags to the @mflac_of array. If there's tag fields
# with empty values, ignore those hash elements. They get
# unintentionally created, when using references in other subroutines.
	foreach my $field (sort(keys(%{$$tags_of_ref}))) {
		my $tag_ref = \$$tags_of_ref->{$field};

		if (! length($$tag_ref)) { next; }

		unless ($field eq 'vendor_ref') {
			push(@mflac_of, uc($field) . '=' . $$tag_ref);
		}
	}

# Check if there's a difference between the input and output tags.
	if (scalar(@mflac_if) != scalar(@mflac_of)) {
		$is_equal = 0;
	} else {
		for (my $i = 0; $i < scalar(@mflac_if); $i++) {
			if ($mflac_if[$i] ne $mflac_of[$i]) {
				$is_equal = 0;
				last;
			}
		}
	}

	if ($is_equal == 0) {
# Import the tags from the @mflac_of array.
		system('metaflac', '--remove-all-tags', $fn);
		or_warn("Can't remove tags");
		open(my $input, '|-', 'metaflac', '--import-tags-from=-', $fn)
		or die "Can't import tags: $!";
		while (my $line = shift(@mflac_of)) { say $input $line; }
		close($input) or die "Can't close 'metaflac': $!";
	}
}

# The 'tags2fn' subroutine creates a new path and file name for the
# input files, based on the changes that have been made to the tags.
sub tags2fn {
	my $fn = shift;
	my($newbn, $newdn, $newfn);
	my($discnumber, $albumartist, $album, $tracknumber, $title);

	sub rm_special_chars {
		my $string = shift;
		$string =~ tr/a-zA-Z0-9\.\-_ //dc;

		return($string);
	}

	$discnumber = $$discnumber_ref;
	$albumartist = rm_special_chars($$albumartist_ref);
	$albumartist =~ s/ +/ /g;
	$albumartist =~ s/^\.+//g;
	$album = rm_special_chars($$album_ref);
	$album =~ s/ +/ /g;
	$album =~ s/^\.+//g;
	$tracknumber = sprintf("%02d", $$tracknumber_ref);
	$title = rm_special_chars($$title_ref);
	$title =~ s/ +/ /g;
	$newbn = $discnumber . '-' . $tracknumber . '. ' . $title . '.flac';
	$newdn = $library . '/' . $albumartist . '/' . $album;
	$newfn = $newdn . '/' . $newbn;

	if (! -d $newdn) {
		make_path($newdn) or die "Can't create directory: $!";
	}

	if (! -f $newfn) {
		move($fn, $newfn) or die "Can't rename '$fn': $!";
		say $fn . ': renamed based on tags';
	}

# If the input directory contains other filetypes besides FLAC, move
# those files to the new directory. This may include log files, etc.
	if (length($files{other})) {
		foreach my $fn (keys(%{$files{other}})) {
			$newfn = $newdn . '/' . basename($fn);

			if (! -f $newfn) {
				move($fn, $newfn) or die "Can't rename '$fn': $!";
			}
		}

		delete($files{other});
	}
}

# The 'totaltracks' subroutine creates the TOTALTRACKS tag, if it
# doesn't exist already.
sub totaltracks {
	my $fn = shift;

	my(%tracks, $tracks);

	if ($$tracknumber_ref =~ m/$regex{fraction}/) {
		$$tracknumber_ref = $1;

		if (! lengh($$totaltracks_ref)) {
			$$totaltracks_ref = $2;
		}
	}

	if (length($$discnumber_ref)) {
		foreach my $fn (keys(%tags_of)) {
			my $discnumber_ref = \$tags_of{$fn}{discnumber};

			if (length($$discnumber_ref)) {
				${tracks}{$$discnumber_ref}++;
			}
		}

		$tracks = ${tracks}{$$discnumber_ref};

		if (! length($$totaltracks_ref) and ! length($$tracktotal_ref)) {
			$$totaltracks_ref = $tracks;
		}
	}

	if (length($$tracktotal_ref) and ! length($$totaltracks_ref)) {
		$$totaltracks_ref = $$tracktotal_ref;
	}
}

# The 'rm_empty_dirs' subroutine finds all the empty sub-directories
# under the FLAC library directory, and removes them.
sub rm_empty_dirs {
	sub read_find {
		open(my $find, '-|', 'find', $library, ,'-mindepth', '1', '-type', 'd', '-empty', '-nowarn')
		or die "Can't open 'find': $!";
		chomp(my @lines = (<$find>));
		close($find) or die "Can't close 'find': $!";

		return(@lines);
	}

	my @lines = (read_find());

	while (scalar(@lines)) {
		foreach my $fn (@lines) {
			rmdir($fn) or die "Can't remove '$fn': $!";
		}

		@lines = (read_find());
	}
}
