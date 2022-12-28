#!/usr/bin/perl

# This script is meant to import FLAC albums to a FLAC music library
# directory.

use v5.34;
use strict;
use warnings;
use Cwd qw(abs_path);
use File::Basename qw(basename);
use File::Find qw(find);
use File::Path qw(make_path);
use File::Copy qw(copy);
use Encode qw(decode find_encoding);

my @lacc = qw(EAC 'Exact Audio Copy' 'XLD X Lossless Decoder' cdparanoia Rubyripper whipper);
my(%regex, %tags, %files, @dirs, @log, $library);
my($discnumber_ref, $tracknumber_ref);
my($artist_ref, $albumartist_ref, $album_ref, $title_ref);

$regex{quote} = qr/^(\")|(\")$/;
$regex{space} = qr/(^\s*)|(\s*$)/;
$regex{tag} = qr/^([^=]+)=(.*)$/;

# Check if the necessary commands are installed to test FLAC files.
my $flac_req = `command -v metaflac`;

if (! length($flac_req)) {
	say "\n" . 'This script needs \'metaflac\' installed!' . "\n";
	exit
}

while (my $arg = shift(@ARGV)) {
	if (-d $arg) {
		push(@dirs, abs_path($arg));
	} else { usage(); }
}

if (scalar(@dirs) < 2) { usage(); }

$library = shift(@dirs);

# The 'usage' subroutine prints syntax, and then quits.
sub usage {
	say "\n" . 'Usage: ' . basename($0) . ' [FLAC library directory] .. [directory N]' . "\n";
	exit;
}

# The 'getfiles' subroutine gets a list of FLAC files in the directory
# passed to it.
sub getfiles {
	my $dn = shift;

	undef(%files);
	undef(%tags);
	undef(@log);

	opendir(my $dh, $dn) or die "Can't open directory '$dn': $!";
	foreach my $bn (readdir($dh)) {
		my $fn = $dn . '/' . $bn;

		if (! -f $fn) { next; }

		if ($bn =~ /\.flac$/i) { $files{$fn} = { gettags($fn) }; }
		if ($bn =~ /\.log$/i) { check_log($fn); }
	}
	closedir $dh or die "Can't close directory '$dn': $!";

	foreach my $fn (keys(%files)) {
		my $tags_ref = \$files{$fn};

		foreach my $field (keys(%{$files{$fn}})) {
			$tags{$fn}{$field} = $$tags_ref->{$field}[0];
		}
	}
}

# The 'gettags' subroutine reads the tags from a FLAC file.
sub gettags {
	my $fn = shift;

	my(%alltags, @lines);

	open(my $output, '-|', 'metaflac', '--no-utf8-convert', '--export-tags-to=-', $fn)
	or die "Can't open metaflac: $!";
	chomp(@lines = (<$output>));
	close($output) or die "Can't close metaflac: $!";

	while (my $line = shift(@lines)) {
		my(@tag, $field, $value);

		$line =~ s/$regex{quote}//g;

		if ($line =~ m/$regex{tag}/) {
			$field = lc($1);
			$value = $2;

			$field =~ s/$regex{space}//;
			$value =~ s/$regex{space}//;
			$value =~ tr/a-zA-Z0-9\.\-_ //dc;
			$value =~ s/\s+/ /g;

			if ($field eq 'album' or $field eq 'albumartist') {
				$value =~ s/^\.+//g;
			}
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

	$discnumber_ref = \$tags{$fn}{discnumber};
	$tracknumber_ref = \$tags{$fn}{tracknumber};
	$artist_ref = \$tags{$fn}{artist};
	$albumartist_ref = \$tags{$fn}{albumartist};
	$album_ref = \$tags{$fn}{album};
	$title_ref = \$tags{$fn}{title};
}

# The 'existstag' subroutine checks for the existence of the chosen tags
# passed to it. If it doesn't find the tag, it quits.
sub existstag {
	my $fn = shift;

	my @tags = ('artist', 'album', 'tracknumber', 'title');

	foreach my $field (@tags) {
		if (! length($tags{$fn}{$field})) {
			say $fn . ': doesn\'t have ' . $field . ' tag';
			exit;
		}
	}
}

# The 'albumartist' subroutine creates the ALBUMARTIST tag, if it
# doesn't exist already.
sub albumartist {
	my $fn = shift;
	my $tracks = shift;

	my $artist_ref = \$tags{$fn}{artist};
	my $albumartist_ref = \$tags{$fn}{albumartist};

	if (! length($$albumartist_ref)) {
		my(%artist, $max);

		if ($tracks == 1) { $max = $tracks; } else { $max = $tracks / 2; }

		foreach my $fn (keys(%files)) {
			$artist{$$artist_ref} = 1;
		}

		if (keys(%artist) > $max) {
			$$albumartist_ref = 'Various Artists';
		} else { $$albumartist_ref = $$artist_ref; }
	}
}

# The 'check_log' subroutine checks the log file to see if it contains
# any of the words in @lacc. Most of the code here is to deal with
# correctly decoding the character encoding in the log file. We do this
# to be able to properly match the words.
sub check_log {
	my $fn = shift;
	my($file_output, $file_enc, $enc, $enc_tmp, $line1);

	open(my $info, '-|', 'file', '-i', $fn) or die "Can't run file: $!";
	chomp($file_output = <$info>);
	close($info) or die "Can't close file: $!";

	$file_output =~ /charset=(.*)[[:space:]]*$/;
	$file_enc = $1;

	$enc_tmp = find_encoding($file_enc);

	if (length($enc_tmp)) { $enc = $enc_tmp->name; }

	open(my $text, '< :raw', $fn) or die "Can't open file '$fn': $!";
	$line1 = <$text>;
	$line1 =~ s/(\r){0,}(\n){0,}$//g;
	if (length($enc)) { $line1 = decode($enc, $line1); }
	close $text or die "Can't close file '$fn': $!";

	foreach my $req (@lacc) {
		if ($line1 =~ /$req/) { push(@log, $fn); last; }
	}
}

# The 'import' subroutine imports a FLAC album to the FLAC library.
sub import {
	my $fc = shift;
	my $cp = 0;
	my $cplog = 1;
	my($newfn, $path);

	foreach my $sf (sort(keys(%files))) {
		mk_refs($sf);
		existstag($sf);
		albumartist($sf, $fc);

		$path = $library . '/' . $$albumartist_ref . '/' . $$album_ref;

		if ($cp == 0 and -d $path) {
			say $path . ': already exists';
			say 'Skipping...' . "\n";
			return;
		} else { make_path($path); }

		if (length($$discnumber_ref)) {
			$newfn = sprintf('%s-%02s. %s.flac', $$discnumber_ref, $$tracknumber_ref, $$title_ref);
		} else {
			$newfn = sprintf('%02s. %s.flac', $$tracknumber_ref, $$title_ref);
		}

		my $tf = $path . '/' . $newfn;

		say 'Copying \'' . $sf . '\'' . "\n\t" . 'to \'' . $tf . '\'...';
		copy($sf, $tf) or die "Copy failed: $!";
		$cp++
	}

	say 'Copied ' . $cp . ' / ' . $fc . ' files from \'' . $$album_ref . '\'.' . "\n";

	foreach my $sf (@log) {
		my($tf);

		if (scalar(@log) > 1) {
			$tf = $path . '/' . $cplog . '-' . $$album_ref . '.log';
		} else {
			$tf = $path . '/' . $$album_ref . '.log';
		}

		say 'Copying \'' . $sf . '\'' . "\n\t" . 'to \'' . $tf . '\'...' . "\n";
		copy($sf, $tf) or die "Copy failed: $!";
		$cplog++
	}
}

while (my $dn = shift(@dirs)) {
	find({ wanted => \&action, no_chdir => 1 }, $dn);

	sub action {
		if (-d) {
			my $dn = $File::Find::name;
			getfiles($dn);
			my $fc = keys(%files);
			if ($fc > 0) {
				say $dn . ': importing...' . "\n";
				import($fc);
			} else { say $dn . ': contains no FLAC files'; }
		}
	}
}
