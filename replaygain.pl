#!/usr/bin/perl
# This script is meant to manage my FLAC music library, specifically the
# tags.

# This script will:

# * Remove empty tags and duplicate tag fields
# * Remove leading and trailing whitespace from tags
# * Check FLAC version and re-encode (-8) if an older version than:
# $flac_version[1] (the installed version of 'flac')
# * Remove ID3v2 tags while re-encoding, but keep VorbisComment tags
# * Remove tags (only RATING as of right now)
# * Add DISCNUMBER, ALBUMARTIST, TOTALTRACKS tags
# * Remove leading 0s from TRACKNUMBER tags
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

use v5.34;
use strict;
use warnings;
use File::Copy qw(move);
use File::Basename qw(basename dirname);
use File::Path qw(make_path);
use Cwd qw(abs_path);

my $script = basename($0);
my(@flac_version, $library, %t, %files, @files, @dirs, %mflac_if, @mflac_of);

# The 'version' subroutine checks the installed version of 'flac'.
sub version {
	my(@lines);

	open(my $flac_v, '-|', 'flac', '--version') or die "Can't open 'flac': $!";
	chomp(@lines = (<$flac_v>));
	close($flac_v) or die "Can't close 'flac': $!";

	@flac_version = split(' ', $lines[0]);
}

version();

if (defined($ARGV[0])) {
	if (scalar(@ARGV) != 1 or ! -d $ARGV[0]) {
		usage();
	} else { $library = abs_path($ARGV[0]); }
} else {
	usage();
}

# Find all the sub-directories under the FLAC library directory.
getdirs($library);

# This is the main loop of the script, it calls most of the subroutines.
foreach my $dn (@dirs) {
	getfiles($dn);
	my $fc = scalar(@files);
	if ($fc > 0) {
		for (my $n = 0; $n < $fc; $n++) {
			my $fn = $files[$n];
			undef(%t);
			foreach my $tag (keys( %{ $files{$fn} } )) {
				$t{$tag} = $files{$fn}{$tag}->[0];
			}
			existstag($fn, 'artist', 'album', 'title', 'tracknumber');
			vendor($fn);
			rmtag($fn, 'rating');
			discnum($fn);
			albumartist($fn);
			tracknum($fn);
# rm_albumart($fn);
			writetags($fn);
		}
	}
}

# Running this loop after the first loop, because it renames the FLAC
# files.
foreach my $dn (@dirs) {
	getfiles($dn);
	my $fc = scalar(@files);
	if ($fc > 0) {
		for (my $n = 0; $n < $fc; $n++) {
			my $fn = $files[$n];
			undef(%t);
			foreach my $tag (keys( %{ $files{$fn} } )) {
				$t{$tag} = $files{$fn}{$tag}->[0];
			}
			tags2fn($fn);
		}
	}
}

# Remove all the empty sub-directories in the FLAC library directory,
# since files may have been moved by the 'tags2fn' subroutine.
rm_empty_dirs();

# Find all the sub-directories under the FLAC library directory. We're
# checking the sub-directories a second time, because they may have
# changed due to the 'tags2fn' subroutine being run.
getdirs($library);

# Adding the TOTALTRACKS tag last, because we need to do that after the
# files have been moved to the proper directories. The same rule applies
# to the ReplayGain tags.
foreach my $dn (@dirs) {
	getfiles($dn);
	my $fc = scalar(@files);
	if ($fc > 0) {
		replaygain($dn);

		for (my $n = 0; $n < $fc; $n++) {
			my $fn = $files[$n];
			undef(%t);
			foreach my $tag (keys( %{ $files{$fn} } )) {
				$t{$tag} = $files{$fn}{$tag}->[0];
			}
			totaltracks($fn);
			writetags($fn);
		}
	}
}

# The 'usage' subroutine prints syntax, and then quits.
sub usage {
	say "Usage: $script [FLAC library directory]\n";
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
# library directory.
sub getdirs {
	my $dn = shift;

	undef(@dirs);

	open(my $find, '-|', 'find', $dn, '-type', 'd', '-iname', '*') or die "Can't open 'find': $!";
	chomp(@dirs = (<$find>));
	close($find) or die "Can't close 'find': $!";
}

# The 'getfiles' subroutine gets the list of FLAC files in the directory
# passed to it.
sub getfiles {
	my $dn = shift;
	my(@lines);

	undef(%files);
	undef(@files);
	undef(%mflac_if);

	open(my $find, '-|', 'find', $dn, '-mindepth', '1', '-maxdepth', '1', '-type', 'f', '-iname', '*') or die "Can't open 'find': $!";
	chomp(@lines = (<$find>));
	close($find) or die "Can't close 'find': $!";

	foreach my $fn (@lines) {
		if ($fn =~ m/.flac$/i) {
			push(@files, $fn);
			$files{$fn} = { gettags($fn) };
		}
	}
}

# The 'gettags' subroutine reads the tags from the FLAC file.
sub gettags {
	my $fn = shift;
	my(%alltags, @lines);

	open(my $output, '-|', 'metaflac', '--no-utf8-convert', '--show-vendor-tag', '--export-tags-to=-', $fn) or die "Can't open 'metaflac': $!";
	chomp(@lines = (<$output>));
	close($output) or die "Can't close 'metaflac': $!";

	foreach (@lines) {
		my(@tag, $tagname);

		if (/^reference/) {
			@tag = split(' ');
			$tagname = 'vendor_ref';

			if (defined($tag[2])) {
				$tag[1] = $tag[2];
			} else {
				undef(@tag);
				$tag[1] = $_;
			}
		} else {
			push(@{$mflac_if{$fn}}, $_);
			@tag = split('=');

			if (defined($tag[0])) {
				$tagname = lc($tag[0]);
			} else { next; }

			if (defined($tag[1])) {
				$tag[1] =~ s/(^\s*)|(\s*$)//g;
			} else { next; }
		}

		if (defined($tag[1])) {
			push(@{$alltags{$tagname}}, $tag[1]);
		}
	}

	return(%alltags);
}

# The 'existstag' subroutine checks for the existence of the chosen tags
# passed to it. If it doesn't find the tag, it quits.
sub existstag {
	my $fn = shift;
	my $switch = 0;

	foreach my $tag (@_) {
		if (! defined($t{$tag})) {
			say $fn . ': doesn\'t have ' . $tag . ' tag';
			$switch = 1;
			last;
		}
	}

	if ($switch == 1) { exit; }
}

# The 'vendor' subroutine re-encodes the FLAC file, if it was encoded
# with an old version of FLAC. If the FLAC has ID3v2 tags, they will be
# removed in the process of decoding the FLAC to WAV, before re-encoding
# it.
sub vendor {
	my $fn = shift;
	my($newfn, $newfn_flac, $newfn_wav, $newfn_stderr, $newfn_art);

	sub sigint {
		say "Interrupted by user!";
		foreach my $fn (@_) {
			if (-f $fn) {
				unlink($fn) or die "Can't remove '$fn': $!";
			}
		}
		exit;
	}

	if (! defined($t{vendor_ref}) or $t{vendor_ref} ne $flac_version[1]) {
		$newfn = $fn;
		$newfn =~ s/.[[:alnum:]]{3,4}$//i;
		$newfn = $newfn . '-' . int(rand(10000));
		$newfn_flac = $newfn . '.flac';
		$newfn_wav = $newfn . '.wav';
		$newfn_art = $newfn . '.albumart';
		$newfn_stderr = $newfn . '.stderr';

		print $fn . ': ' . 'old encoder (' . $t{vendor_ref} . '), re-encoding... ';

# Duplicate STDERR (for restoration later).
# Redirect STDERR to a file ($newfn_stderr).
		open(my $olderr, ">&STDERR") or die "Can't dup STDERR: $!";
		close(STDERR) or die "Can't close STDERR: $!";
		open(STDERR, '>', $newfn_stderr) or die "Can't open '$newfn_stderr': $!";

		system('flac', '--silent', '-8', $fn, "--output-name=$newfn_flac");
		or_warn("Can't encode file");

# Close the STDERR file ($newfn_stderr).
# Restore STDERR from $olderr.
# Close the $olderr filehandle.
		close(STDERR) or die;
		open(STDERR, ">&", $olderr) or die "Can't dup STDERR: $!";
		close($olderr) or die "Can't close STDERR: $!";

		if ($? == 0) {
			move($newfn_flac, $fn) or die "Can't rename '$newfn_flac': $!";

			say 'done';
		} elsif ($? == 2) {
			sigint($newfn_flac, $newfn_stderr);
		} else {
# Open a filehandle that reads from the STDERR file ($newfn_stderr).
# Save the content of the file in an array (@stderra).
			open(my $fh_stderrf, '<', $newfn_stderr) or die "Can't open '$newfn_stderr': $!";
			chomp(my @stderra = (<$fh_stderrf>));
			close($fh_stderrf) or die "Can't close '$newfn_stderr': $!";

			foreach (@stderra) {
				if (/has an ID3v2 tag/) {
					print "\n" . $fn . ': ' . 'replacing ID3v2 tags with VorbisComment... ';

# Decode the FLAC file to WAV (in order to lose the ID3v2 tags).
					system('flac', '--silent', '--decode', $fn, "--output-name=$newfn_wav");
					or_warn("Can't decode file");

					if ($? == 2) {
						sigint($newfn_wav, $newfn_stderr);
					}

# Back up the album art, if it exists.
					system("metaflac --export-picture-to=\"$newfn_art\" \"$fn\" 1>&- 2>&-");

# Encode the WAV file to FLAC.
					if (-f $newfn_art) {
						system('flac', '--silent', '-8', "--picture=$newfn_art", $newfn_wav, "--output-name=$newfn_flac");
						or_warn("Can't encode file");

						unlink($newfn_art) or die "Can't remove '$newfn_art': $!";
					} else {
						system('flac', '--silent', '-8', $newfn_wav, "--output-name=$newfn_flac");
						or_warn("Can't encode file");
					}

					unlink($newfn_wav) or die "Can't remove '$newfn_wav': $!";

					if ($? == 0) {
						move($newfn_flac, $fn) or die "Can't move '$newfn_flac': $!";

						say 'done';

# Clearing the %mflac_if hash key representing $fn, to force the
# 'writetags' subroutine to rewrite the tags. They were removed in the
# decoding process.
						@{$mflac_if{$fn}} = ();
					} elsif ($? == 2) {
						sigint($newfn_wav, $newfn_flac, $newfn_stderr);
					}
				}
			}
		}
# Delete the STDERR file.
		unlink($newfn_stderr) or die "Can't remove '$newfn_stderr': $!";
	}
}

# The 'rmtag' subroutine removes tags of choice.
sub rmtag {
	my $fn = shift;

	foreach my $tag (@_) {
		if (defined($t{$tag})) {
			say $fn . ': removing ' . $tag . ' tag';
			delete($t{$tag});
		}
	}
}

# The 'discnum' subroutine creates the DISCNUMBER tag, if it doesn't
# exist already. This subroutine needs to be run before 'albumartist',
# and 'totaltracks'.
sub discnum {
	my $fn = shift;
	my($disc_str);

	my $dn = dirname($fn);
	my $regex = qr/\s*[[:punct:]]?(cd|disc)\s*[0-9]+(\s*of\s*[0-9]+)?[[:punct:]]?\s*$/pi;
	my $regex2 = qr/\s*of\s*[0-9]+[[:punct:]]?\s*$/pi;
	my $regex3 = qr/[0-9]+/p;

# Cleaning up DISCNUMBER, TOTALDISCS and DISCTOTAL tags, if they exist.
	if (defined($t{discnumber})) {
		$t{discnumber} =~ m/$regex3/;
		$t{discnumber} = ${^MATCH};
	}

	if (defined($t{totaldiscs})) {
		$t{totaldiscs} =~ m/$regex3/;
		$t{totaldiscs} = ${^MATCH};
	}

	if (defined($t{disctotal})) {
		$t{disctotal} =~ m/$regex3/;
		$t{disctotal} = ${^MATCH};
	}

# Adding the DISCNUMBER tag.
	if (! defined($t{discnumber})) {
		if ($t{album} =~ m/$regex/) {
			$disc_str = ${^MATCH};
			${^MATCH} =~ m/$regex3/;
			$t{discnumber} = ${^MATCH};
			$t{album} =~ s/$regex//;

			say $fn . ': adding discnumber tag';
		}
	}

	if (! defined($t{discnumber})) {
		if ($dn =~ m/$regex/) {
			$disc_str = ${^MATCH};
			${^MATCH} =~ m/$regex3/;
			$t{discnumber} = ${^MATCH};
		} else {
			$t{discnumber} = 1;
		}

		say $fn . ': adding discnumber tag';
	}

# Let's add the TOTALDISCS tag as well, if possible.
	if (! defined($t{totaldiscs})) {
		if (defined($t{disctotal})) {
			$t{totaldiscs} = $t{disctotal};

			say $fn . ': adding totaldiscs tag';
		}
	}

	if (! defined($t{totaldiscs}) && defined($disc_str)) {
		if ($disc_str =~ m/$regex2/) {
			${^MATCH} =~ m/$regex3/;
			$t{totaldiscs} = ${^MATCH};

			say $fn . ': adding totaldiscs tag';
		}
	}

	if (defined($t{discnumber})) {
		if (! defined($files{$fn}{discnumber}->[0])) {
			$files{$fn}{discnumber}->[0] = $t{discnumber};
		} elsif ($files{$fn}{discnumber}->[0] ne $t{discnumber}) {
			$files{$fn}{discnumber}->[0] = $t{discnumber};
		}
	}
}

# The 'albumartist' subroutine creates the ALBUMARTIST tag, if it
# doesn't exist already.
sub albumartist {
	my $fn = shift;

	my($tracks, %tracks);

	if (defined($t{discnumber})) {
		foreach my $fn (@files) {
			if (defined($files{$fn}{discnumber}->[0])) {
				${tracks}{$files{$fn}{discnumber}->[0]}++;
			}
		}

		$tracks = ${tracks}{$t{discnumber}};

		if (! defined($t{albumartist})) {
			my(%artist, $max);

			if ($tracks == 1) { $max = $tracks; } else { $max = $tracks / 2; }

			foreach my $fn (keys(%files)) {
				$artist{$files{$fn}{artist}->[0]} = 1;
			}

			if (keys(%artist) > $max) {
				$t{albumartist} = 'Various Artists';
			} else { $t{albumartist} = $t{artist}; }

			say $fn . ': adding albumartist tag';
		}
	}
}

# The 'tracknum' subroutine removes leading 0s from the TRACKNUMBER tag.
sub tracknum {
	my $fn = shift;

	my $regex = qr/[0-9]+/p;
	my $regex2 = qr/^0+$/;
	my $regex3 = qr/^0+/;

	if (defined($t{tracknumber})) {
		my $old_tag = $t{tracknumber};

		$t{tracknumber} =~ m/$regex/;
		$t{tracknumber} = ${^MATCH};

		if ($t{tracknumber} =~ m/$regex2/) {
			$t{tracknumber} = 0;
		} elsif ($t{tracknumber} =~ m/$regex3/) {
			$t{tracknumber} =~ s/$regex3//;
		}

		if ($t{tracknumber} ne $old_tag) {
			say $fn . ': fixing tracknumber tag';
		}
	}
}

# The 'rm_albumart' subroutine removes the album art, by removing the
# PICTURE metadata block.
sub rm_albumart {
	my $fn = shift;

	say $fn . ': removing album art';

	system('metaflac', '--remove', ,'--block-type=PICTURE', $fn);
	or_warn("Can't remove album art");
}

# The 'replaygain' subroutine adds ReplayGain tags, if they don't exist
# already.
sub replaygain {
	my $dn = shift;
	my(%replaygain);

	foreach my $fn (sort(keys %files)) {
		if (defined($files{$fn}{replaygain_album_gain}->[0])) {
			$replaygain{$files{$fn}{replaygain_album_gain}->[0]}++;
		}
	}

	if (keys(%replaygain) != 1) {
		print "$dn: adding ReplayGain... ";

		system('metaflac', '--remove-replay-gain', keys(%files));
		or_warn("Can't remove ReplayGain");
		system('metaflac', '--add-replay-gain', keys(%files));
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
	my $is_equal = 1;

	undef(@mflac_of);

# Sort the keys in the hash that contains all the tags.
# Then push the tags to the @mflac_of array.
	foreach my $tag (sort(keys(%t))) {
		unless ($tag eq 'vendor_ref') {
			if (defined($t{$tag})) {
				push(@mflac_of, uc($tag) . '=' . $t{$tag});
			}
		}
	}

	if (scalar(@{$mflac_if{$fn}}) != scalar(@mflac_of)) {
		$is_equal = 0;
	} else {
		for (my $i = 0; $i < scalar(@{$mflac_if{$fn}}); $i++) {
			if ($mflac_if{$fn}->[$i] ne $mflac_of[$i]) {
				$is_equal = 0;
				last;
			}
		}
	}

	if ($is_equal == 0) {
# Import the tags from the @mflac_of array.
		system('metaflac', '--remove-all-tags', $fn);
		or_warn("Can't remove tags");
		open(my $output, '|-', 'metaflac', '--import-tags-from=-', $fn) or die "Can't import tags: $!";
		foreach my $line (@mflac_of) {
			say $output $line;
		}
		close($output) or die "Can't close 'metaflac': $!";
	}
}

# The 'tags2fn' subroutine creates a new path and file name for the
# input files, based on the changes that have been made to the tags.
sub tags2fn {
	my $fn = shift;
	my $dn = dirname($fn);

	sub rm_special_chars {
		my $string = shift;
		$string =~ tr/a-zA-Z0-9\.\-_ //dc;

		return($string);
	}

	my $discnum = $t{discnumber};
	my $albumartist = rm_special_chars($t{albumartist});
	$albumartist =~ s/ +/ /g;
	$albumartist =~ s/^\.+//g;
	my $album = rm_special_chars($t{album});
	$album =~ s/ +/ /g;
	$album =~ s/^\.+//g;
	my $tracknum = sprintf("%02d", $t{tracknumber});
	my $title = rm_special_chars($t{title});
	$title =~ s/ +/ /g;
	my $newfn_bn = $discnum . '-' . $tracknum . '. ' . $title . '.flac';
	my $newdn_dn = $library . '/' . $albumartist . '/' . $album;
	my $newfn = $newdn_dn . '/' . $newfn_bn;

	if (! -d $newdn_dn) {
		make_path($newdn_dn) or die "Can't create directory: $!";
	}

	if (! -f $newfn) {
		say $fn . ': renaming based on tags';
		move($fn, $newfn) or die "Can't rename '$fn': $!";
	}
}

# The 'totaltracks' subroutine creates the TOTALTRACKS tag, if it
# doesn't exist already.
sub totaltracks {
	my $fn = shift;

	my($tracks, %tracks);

	if (defined($t{discnumber})) {
		foreach (@files) {
			if (defined($files{$_}{discnumber}->[0])) {
				${tracks}{$files{$_}{discnumber}->[0]}++;
			}
		}

		$tracks = ${tracks}{$t{discnumber}};

		if (! defined($t{totaltracks}) && ! defined($t{tracktotal})) {
			say $fn . ': adding totaltracks tag';
			$t{totaltracks} = $tracks;
		}
	}

	if (defined($t{tracktotal}) && ! defined($t{totaltracks})) {
		say $fn . ': adding totaltracks tag';
		$t{totaltracks} = $t{tracktotal};
	}
}

# The 'rm_empty_dirs' subroutine finds all the empty sub-directories
# under the FLAC library directory, and removes them.
sub rm_empty_dirs {
	sub read_find {
		open(my $find, '-|', 'find', $library, ,'-mindepth', '1', '-type', 'd', '-empty') or die "Can't open 'find': $!";
		chomp(my @lines = (<$find>));
		close($find) or die "Can't close 'find': $!";

		return(@lines);
	}

	my @lines = (read_find());

	while (scalar(@lines) > 0) {
		foreach my $fn (@lines) {
			rmdir($fn) or die "Can't remove '$fn': $!";
		}

		@lines = (read_find());
	}
}
