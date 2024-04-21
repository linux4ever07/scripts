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
use diagnostics;
use File::Copy qw(move);
use File::Basename qw(basename dirname);
use File::Path qw(make_path);
use Cwd qw(abs_path);

my @required_tags = qw(artist album tracknumber title);
my(%regex, %files, %tags_if, %tags_of, %tags_ref, @dirs, $library, $depth_og);

$regex{fn} = qr/^(.*)\.([^.]*)$/;
$regex{newline} = qr/(\r){0,}(\n){0,}$/;
$regex{quote} = qr/^(\")|(\")$/;
$regex{space} = qr/(^\s*)|(\s*$)/;
$regex{zero} = qr/^0+([0-9]+)$/;
$regex{tag} = qr/^([^=]+)=(.*)$/;
$regex{fraction} = qr/^([0-9]+)\s*\/\s*([0-9]+)$/;
$regex{disc} = qr/\s*[[:punct:]]?(cd|disc)\s*([0-9]+)(\s*of\s*([0-9]+))?[[:punct:]]?\s*$/i;
$regex{id3v2} = qr/has an ID3v2 tag/;

# Check if the necessary commands are installed to test FLAC files.
chomp(my @flac_req = (`command -v flac metaflac`));

if (scalar(@flac_req) != 2) {
	say "\n" . 'This script needs \'flac\' and \'metaflac\' installed!' . "\n";
	exit;
}

# Check the installed version of 'flac'.
my @flac_version = split(' ', `flac --version`);

if (scalar(@ARGV) != 1 or ! -d $ARGV[0]) { usage(); }

$library = abs_path($ARGV[0]);
$depth_og = scalar(split('/', $library));

# Find all the sub-directories under the FLAC library directory.
get_dirs();

# This is the main loop of the script, it calls most of the subroutines.
foreach my $dn (@dirs) {
	get_files($dn);

	foreach my $fn (sort(keys(%{$files{flac}}))) {
		mk_refs($fn);
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
	get_files($dn);

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
get_dirs();

# Adding the TOTALTRACKS tag last, because we need to do that after the
# files have been moved to the proper directories. The same rule applies
# to the ReplayGain tags.
foreach my $dn (@dirs) {
	get_files($dn);

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

# The 'get_dirs' subroutine finds all the sub-directories under the FLAC
# library directory. The list of directories is sorted with the deepest
# directories first.
sub get_dirs {
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

# The 'get_files' subroutine gets a list of FLAC files in the directory
# passed to it.
sub get_files {
	my $dn = shift;

	my(@lines);

	undef(%files);
	undef(%tags_if);
	undef(%tags_of);

	open(my $find, '-|', 'find', $dn, '-mindepth', '1', '-maxdepth', '1', '-type', 'f', '-nowarn')
	or die "Can't open 'find': $!";
	chomp(@lines = (<$find>));
	close($find) or die "Can't close 'find': $!";

	while (my $fn = shift(@lines)) {
		if ($fn =~ m/\.flac$/i) {
			$files{flac}{$fn} = { gettags($fn) };
		} else {
			$files{other}{$fn} = ();
		}
	}

	foreach my $fn (keys(%{$files{flac}})) {
		my $tags_ref = \$files{flac}{$fn};

		existstag($fn, $tags_ref, @required_tags);

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

			$field =~ s/$regex{space}//g;
			$value =~ s/$regex{space}//g;
		}

		if (! length($field) or ! length($value)) { next; }

		push(@{$alltags{$field}}, $value);
	}

	return(%alltags);
}

# The 'existstag' subroutine checks for the existence of required tags.
# If it doesn't find them, it quits.
sub existstag {
	my $fn = shift;
	my $tags_ref = shift;

	my(@missing_tags);

	while (my $field = shift(@_)) {
		if (length($$tags_ref->{$field}[0])) { next; }

		push(@missing_tags, $field);
	}

	if (! scalar(@missing_tags)) { return; }

	foreach my $field (@missing_tags) {
		say $fn . ': missing ' . $field . ' tag';
	}

	exit;
}

# The 'mk_refs' subroutine creates references for other subroutines to
# have easier access to tags.
sub mk_refs {
	my $fn = shift;

	$tags_ref{discnumber} = \$tags_of{$fn}{discnumber};
	$tags_ref{totaldiscs} = \$tags_of{$fn}{totaldiscs};
	$tags_ref{disctotal} = \$tags_of{$fn}{disctotal};
	$tags_ref{tracknumber} = \$tags_of{$fn}{tracknumber};
	$tags_ref{totaltracks} = \$tags_of{$fn}{totaltracks};
	$tags_ref{tracktotal} = \$tags_of{$fn}{tracktotal};
	$tags_ref{artist} = \$tags_of{$fn}{artist};
	$tags_ref{albumartist} = \$tags_of{$fn}{albumartist};
	$tags_ref{album} = \$tags_of{$fn}{album};
	$tags_ref{title} = \$tags_of{$fn}{title};
	$tags_ref{vendor} = \$tags_of{$fn}{vendor_ref};
}

# The 'vendor' subroutine re-encodes the FLAC file, if it was encoded
# with an old version of FLAC. If the FLAC has ID3v2 tags, they will be
# removed in the process of decoding the FLAC to WAV, before re-encoding
# it.
sub vendor {
	my $if = shift;

	my($of, $of_flac, $of_wav, $of_art, $of_stderr, $has_id3v2);
	$has_id3v2 = 0;

	sub sigint {
		say "Interrupted by user!";

		while (my $fn = shift(@_)) {
			if (! -f $fn) { next; }

			unlink($fn) or die "Can't remove '$fn': $!";
		}

		exit;
	}

	unless (! length(${$tags_ref{vendor}}) or ${$tags_ref{vendor}} ne $flac_version[1]) {
		return;
	}

	$of = $if;
	$of =~ m/$regex{fn}/;
	$of = $1;
	$of = $of . '-' . int(rand(10000));

	$of_flac = $of . '.flac';
	$of_wav = $of . '.wav';
	$of_art = $of . '.albumart';
	$of_stderr = $of . '.stderr';

	print $if . ': old encoder (' . ${$tags_ref{vendor}} . '), re-encoding... ';

# Duplicate STDERR (for restoration later).
# Redirect STDERR to a file ($of_stderr).
	open(my $stderr_dup, ">&STDERR") or die "Can't dup STDERR: $!";
	close(STDERR) or die "Can't close STDERR: $!";
	open(STDERR, '>', $of_stderr) or die "Can't open '$of_stderr': $!";

	system('flac', '--silent', '-8', $if, "--output-name=$of_flac");
	or_warn("Can't encode file");

# Close the STDERR file ($of_stderr).
# Restore STDERR from $stderr_dup.
# Close the $stderr_dup filehandle.
	close(STDERR) or die "Can't close STDERR: $!";
	open(STDERR, ">&", $stderr_dup) or die "Can't dup STDERR: $!";
	close($stderr_dup) or die "Can't close STDERR: $!";

	if ($? == 0) {
		move($of_flac, $if) or die "Can't rename '$of_flac': $!";
		say 'done';
	} elsif ($? == 2) {
		sigint($of_flac, $of_stderr);
	} else {
# Open a filehandle that reads from the STDERR file ($of_stderr).
# Checks if FLAC file has ID3v2 tags.
		open(my $stderr_fh, '<', $of_stderr)
		or die "Can't open '$of_stderr': $!";
		while (chomp(my $line = <$stderr_fh>)) {
			if ($line =~ m/$regex{id3v2}/) {
				$has_id3v2 = 1;
				last;
			}
		}
		close($stderr_fh) or die "Can't close '$of_stderr': $!";

		if (! $has_id3v2) { last; }

		print "\n" . $if . ': ' . 'replacing ID3v2 tags with VorbisComment... ';

# Decode the FLAC file to WAV (in order to lose the ID3v2 tags).
		system('flac', '--silent', '--decode', $if, "--output-name=$of_wav");
		or_warn("Can't decode file");

		if ($? == 2) { sigint($of_wav, $of_stderr); }

# Back up the album art, if it exists.
		system("metaflac --export-picture-to=\"$of_art\" \"$if\" 1>&- 2>&-");

# Encode the WAV file to FLAC.
		if (-f $of_art) {
			system('flac', '--silent', '-8', "--picture=$of_art", $of_wav, "--output-name=$of_flac");
			or_warn("Can't encode file");

			unlink($of_art)
			or die "Can't remove '$of_art': $!";
		} else {
			system('flac', '--silent', '-8', $of_wav, "--output-name=$of_flac");
			or_warn("Can't encode file");
		}

		unlink($of_wav)
		or die "Can't remove '$of_wav': $!";

		if ($? == 0) {
			move($of_flac, $if)
			or die "Can't move '$of_flac': $!";
			say 'done';

# Rewrite the tags. They were removed in the decoding process.
			writetags($if, 0);
		} elsif ($? == 2) {
			sigint($of_wav, $of_flac, $of_stderr);
		}
	}

# Delete the STDERR file.
	unlink($of_stderr) or die "Can't remove '$of_stderr': $!";
}

# The 'rm_tag' subroutine removes tags of choice.
sub rm_tag {
	my $fn = shift;

	while (my $field = shift(@_)) {
		if (! length($tags_of{$fn}{$field})) { next; }

		delete($tags_of{$fn}{$field});
	}
}

# The 'discnumber' subroutine creates the DISCNUMBER tag, if it doesn't
# exist already. DISCTOTAL is also added, if possible. This subroutine
# needs to be run before 'albumartist', and 'totaltracks'.
sub discnumber {
	my $fn = shift;
	my $dn = shift;

	if (length(${$tags_ref{discnumber}})) {
		if (${$tags_ref{discnumber}} =~ m/$regex{fraction}/) {
			${$tags_ref{discnumber}} = $1;

			if (! length(${$tags_ref{totaldiscs}})) {
				${$tags_ref{totaldiscs}} = $2;
			}
		}
	}

	if (! length(${$tags_ref{discnumber}})) {
		if (${$tags_ref{album}} =~ m/$regex{disc}/) {
			${$tags_ref{discnumber}} = $2;

			if (! length(${$tags_ref{totaldiscs}}) and length($4)) {
				${$tags_ref{totaldiscs}} = $4;
			}

			${$tags_ref{album}} =~ s/$regex{disc}//;
		}
	}

	if (! length(${$tags_ref{discnumber}})) {
		if ($dn =~ m/$regex{disc}/) {
			${$tags_ref{discnumber}} = $2;

			if (! length(${$tags_ref{totaldiscs}}) and length($4)) {
				${$tags_ref{totaldiscs}} = $4;
			}
		} else { ${$tags_ref{discnumber}} = 1; }
	}

	if (! length(${$tags_ref{totaldiscs}})) {
		if (length(${$tags_ref{disctotal}})) {
			${$tags_ref{totaldiscs}} = ${$tags_ref{disctotal}};
		}
	}
}

# The 'albumartist' subroutine creates the ALBUMARTIST tag, if it
# doesn't exist already.
sub albumartist {
	my $fn = shift;

	my(%tracks, $tracks);

	if (length(${$tags_ref{discnumber}})) {
		foreach my $fn (keys(%tags_of)) {
			$tags_ref{tmp} = \$tags_of{$fn}{discnumber};

			if (length(${$tags_ref{tmp}})) {
				${tracks}{${$tags_ref{tmp}}}++;
			}
		}

		$tracks = ${tracks}{${$tags_ref{discnumber}}};

		if (! length(${$tags_ref{albumartist}})) {
			my(%artist, $max);

			if ($tracks == 1) { $max = $tracks; }
			else { $max = $tracks / 2; }

			foreach my $fn (keys(%tags_of)) {
				$tags_ref{tmp} = \$tags_of{$fn}{artist};

				$artist{${$tags_ref{tmp}}} = 1;
			}

			if (keys(%artist) > $max) {
				${$tags_ref{albumartist}} = 'Various Artists';
			} else { ${$tags_ref{albumartist}} = ${$tags_ref{artist}}; }
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
		$tags_ref{tmp} = \$tags_of{$fn}{$field};

		if (! length(${$tags_ref{tmp}})) { next; }

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

	if (length(${$tags_ref{tracknumber}})) {
		${$tags_ref{tracknumber}} =~ s/$regex{zero}/$1/;
	}

	if (length(${$tags_ref{totaltracks}})) {
		${$tags_ref{totaltracks}} =~ s/$regex{zero}/$1/;
	}

	if (length(${$tags_ref{tracktotal}})) {
		${$tags_ref{tracktotal}} =~ s/$regex{zero}/$1/;
	}

	if (length(${$tags_ref{discnumber}})) {
		${$tags_ref{discnumber}} =~ s/$regex{zero}/$1/;
	}

	if (length(${$tags_ref{totaldiscs}})) {
		${$tags_ref{totaldiscs}} =~ s/$regex{zero}/$1/;
	}

	if (length(${$tags_ref{disctotal}})) {
		${$tags_ref{disctotal}} =~ s/$regex{zero}/$1/;
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
		$tags_ref{tmp} = \$tags_of{$fn}{replaygain_album_gain};

		if (length(${$tags_ref{tmp}})) {
			$replaygain{${$tags_ref{tmp}}}++;
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

			get_files($dn);
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
			$tags_ref{tmp} = \$$tags_if_ref->{$field}[$i];

			unless ($field eq 'vendor_ref') {
				push(@mflac_if, uc($field) . '=' . ${$tags_ref{tmp}});
			}
		}
	}

# Push the output tags to the @mflac_of array. If there's tag fields
# with empty values, ignore those hash elements. They get
# unintentionally created, when using references in other subroutines.
	foreach my $field (sort(keys(%{$$tags_of_ref}))) {
		$tags_ref{tmp} = \$$tags_of_ref->{$field};

		if (! length(${$tags_ref{tmp}})) { next; }

		unless ($field eq 'vendor_ref') {
			push(@mflac_of, uc($field) . '=' . ${$tags_ref{tmp}});
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
	my $if = shift;

	my($of_dn, $of_bn, $of);
	my($discnumber, $tracknumber, $albumartist, $album, $title);

	sub rm_special_chars {
		my $string = shift;
		$string =~ tr/a-zA-Z0-9\.\-_ //dc;

		return($string);
	}

	$discnumber = ${$tags_ref{discnumber}};
	$tracknumber = ${$tags_ref{tracknumber}};

	if ($discnumber =~ m/$regex{fraction}/) {
		$discnumber = $1;
	}

	if ($tracknumber =~ m/$regex{fraction}/) {
		$tracknumber = $1;
	}

	$tracknumber = sprintf('%02d', $tracknumber);

	$albumartist = rm_special_chars(${$tags_ref{albumartist}});
	$albumartist =~ s/ +/ /g;
	$albumartist =~ s/^\.+//g;
	$album = rm_special_chars(${$tags_ref{album}});
	$album =~ s/ +/ /g;
	$album =~ s/^\.+//g;
	$title = rm_special_chars(${$tags_ref{title}});
	$title =~ s/ +/ /g;

	$of_dn = $library . '/' . $albumartist . '/' . $album;
	$of_bn = $discnumber . '-' . $tracknumber . '. ' . $title . '.flac';
	$of = $of_dn . '/' . $of_bn;

	if (! -d $of_dn) {
		make_path($of_dn) or die "Can't create directory: $!";
	}

	if (! -f $of) {
		move($if, $of) or die "Can't rename '$if': $!";
		say $if . ': renamed based on tags';
	}

# If the input directory contains other filetypes besides FLAC, move
# those files to the new directory. This may include log files, etc.
	if (length($files{other})) {
		foreach my $if (keys(%{$files{other}})) {
			$of = $of_dn . '/' . basename($if);

			if (! -f $of) {
				move($if, $of) or die "Can't rename '$if': $!";
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

	if (${$tags_ref{tracknumber}} =~ m/$regex{fraction}/) {
		${$tags_ref{tracknumber}} = $1;

		if (! length(${$tags_ref{totaltracks}})) {
			${$tags_ref{totaltracks}} = $2;
		}
	}

	if (length(${$tags_ref{discnumber}})) {
		foreach my $fn (keys(%tags_of)) {
			$tags_ref{tmp} = \$tags_of{$fn}{discnumber};

			if (length(${$tags_ref{tmp}})) {
				${tracks}{${$tags_ref{tmp}}}++;
			}
		}

		$tracks = ${tracks}{${$tags_ref{discnumber}}};

		if (! length(${$tags_ref{totaltracks}}) and ! length(${$tags_ref{tracktotal}})) {
			${$tags_ref{totaltracks}} = $tracks;
		}
	}

	if (length(${$tags_ref{tracktotal}}) and ! length(${$tags_ref{totaltracks}})) {
		${$tags_ref{totaltracks}} = ${$tags_ref{tracktotal}};
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
