#!/usr/bin/perl

# This script is meant to import FLAC albums to my FLAC library
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
my (@dirs, @log, %t, %files, $library);

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

# The 'gettags' subroutine reads the tags from a FLAC file.
sub gettags {
	my $fn = shift;
	my(%alltags, @lines);

	my $regex = qr/^(\")|(\")$/;

	open(my $output, '-|', 'metaflac', '--no-utf8-convert', '--export-tags-to=-', $fn)
	or die "Can't open metaflac: $!";
	chomp(@lines = (<$output>));
	close($output) or die "Can't close metaflac: $!";

	foreach my $line (@lines) {
		my (@tag, $tagname);

		$line =~ s/$regex//g;

		@tag = split('=', $line);

		if (! defined($tag[0]) or ! defined($tag[1])) { next; }

		$tagname = lc($tag[0]);
		$tagname =~ s/[[:space:]]//g;
		$tag[1] =~ s/(^\s*)|(\s*$)//g;
		$tag[1] =~ tr/a-zA-Z0-9\.\-_ //dc;
		$tag[1] =~ s/ +/ /g;

		if ($tagname eq 'album' or $tagname eq 'albumartist') {
			$tag[1] =~ s/^\.+//g;
		}

		push(@{$alltags{$tagname}}, $tag[1]);
	}

	return(%alltags);
}

# The 'existstag' subroutine checks for the existence of the chosen tags
# passed to it. If it doesn't find the tag, it quits.
sub existstag {
	my $fn = shift;

	my @tags = ('artist', 'album', 'tracknumber');

	foreach my $tag (@tags) {
		if (! defined($t{$tag}) ) {
			say $fn . ': doesn\'t have ' . $tag . ' tag';
			exit;
		}
	}
}

# The 'getfiles' subroutine gets a list of FLAC files in the directory
# passed to it.
sub getfiles {
	my $dn = shift;

	undef(%files);
	undef(@log);

	opendir(my $dh, $dn) or die "Can't open directory '$dn': $!";
	foreach my $bn (readdir($dh)) {
		my $fn = $dn . '/' . $bn;

		if (! -f $fn) { next; }

		if ($bn =~ /.flac$/i) { $files{$fn} = { gettags($fn) }; }
		if ($bn =~ /.log$/i) { check_log($fn); }
	}
	closedir $dh or die "Can't close directory '$dn': $!";
}

# The 'albumartist' subroutine creates the ALBUMARTIST tag, if it
# doesn't exist already.
sub albumartist {
	my $fn = shift;
	my $tracks = shift;

	if (! defined($t{albumartist})) {
		my(%artist, $max);

		if ($tracks == 1) { $max = $tracks; } else { $max = $tracks / 2; }

		foreach my $fn (keys(%files)) {
			$artist{$files{$fn}{artist}->[0]} = 1;
		}

		if (keys(%artist) > $max) {
			$t{albumartist} = 'Various Artists';
		} else { $t{albumartist} = $t{artist}; }
	}
}

# The 'check_log' subroutine checks the log file to see if it contains
# any of the words in @lacc. Most of the code here is to deal with
# correctly decoding the character encoding in the log file. We do this
# to be able to properly match the words.
sub check_log {
	my $fn = shift;
	my($enc, $line1);

	open(my $info, '-|', 'file', '-i', $fn) or die "Can't run file: $!";
	chomp(my $file_output = <$info>);
	close($info) or die "Can't close file: $!";

	$file_output =~ /charset=(.*)[[:space:]]*$/;
	my $file_enc = $1;

	my $enc_tmp = find_encoding($file_enc);

	if (defined($enc_tmp)) { $enc = $enc_tmp->name; }

	open(my $text, '< :raw', $fn) or die "Can't open file '$fn': $!";
	$line1 = <$text>;
	$line1 =~ s/(\r){0,}(\n){0,}$//g;
	if (defined($enc)) { $line1 = decode($enc, $line1); }
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
	my ($newfn, $path);

	foreach my $sf (sort(keys %files)) {
		undef(%t);

		foreach my $tag (keys(%{$files{$sf}})) {
			$t{$tag} = $files{$sf}{$tag}->[0];
		}

		existstag($sf);
		albumartist($sf, $fc);

		$path = $library . '/' . $t{albumartist} . '/' . $t{album};

		if ($cp == 0 and -d $path) {
			say $path . ': already exists';
			say 'Skipping...' . "\n";
			return;
		} else { make_path($path); }

		if (defined($t{discnumber})) {
		  $newfn = sprintf('%s-%02s. %s.flac', $t{discnumber}, $t{tracknumber}, $t{title});
		} else {
		  $newfn = sprintf('%02s. %s.flac', $t{tracknumber}, $t{title});
		}

		my $tf = $path . '/' . $newfn;

		say 'Copying \'' . $sf . '\'' . "\n\t" . 'to \'' . $tf . '\'...';
		copy($sf, $tf) or die "Copy failed: $!";
		$cp++
	}

	say 'Copied ' . $cp . ' / ' . $fc . ' files from \'' . $t{album} . '\'.' . "\n";

	foreach my $sf (@log) {
		my $tf;

		if (scalar(@log) > 1) {
		  $tf = $path . '/' . $cplog . '-' . $t{album} . '.log';
		} else {
		  $tf = $path . '/' . $t{album} . '.log';
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
