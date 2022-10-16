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

my $script = basename($0);
my @lacc = qw(EAC 'Exact Audio Copy' 'XLD X Lossless Decoder' cdparanoia Rubyripper whipper);
my (@log, %t, %files, $library);

if (defined($ARGV[0])) {
	if (scalar(@ARGV) < 2 or ! -d $ARGV[0]) { usage(); }
	else { $library = abs_path(shift); }
} else { usage(); }

foreach my $dn (@ARGV) {
	if (! -d $dn) {
		say $dn . ': not a directory';
		exit;
	}

	find({ wanted => \&action, no_chdir => 1 }, $dn);

	sub action {
		if (-d) {
			my $dn = abs_path($File::Find::name);
			@log = getfiles($dn);
			my $fc = keys(%files);
			if ($fc > 0) {
				say $dn . ': importing...' . "\n";
				import($fc);
			}
			else {
				say $dn . ': contains no FLAC files';
			}
		}
	}
}

sub usage {
	say 'Usage: ' . $script . ' [FLAC library directory] .. [directory N]' . "\n";
	exit;
}

sub gettags {
	my $fn = shift;
	my (%alltags, @lines);

	my $regex = qr/^(\")|(\")$/;

	open(OUTPUT, '-|', 'metaflac', '--no-utf8-convert', '--export-tags-to=-', $fn)
	or die "Can't open metaflac: $!";
	chomp(@lines = (<OUTPUT>));
	close(OUTPUT) or die "Can't close metaflac: $!";

	foreach (@lines) {
		my (@tag, $tagname);

		$_ =~ s/$regex//g;

		@tag = split('=');

		if (! defined($tag[0] or ! defined($tag[1])) { next; }

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

sub checktags {
	my $fn = shift;

	my @tags = ('artist', 'album', 'tracknumber');

	foreach my $tag (@tags) {
		if (! defined($t{$tag}) ) {
			say $fn . ': doesn\'t have ' . $tag . ' tag';
			exit;
		}
	}
}

sub getfiles {
	my $dn = shift;
	my @log;

	undef %files;

	opendir(my $dh, $dn) or die "Can't open directory '$dn': $!";
	foreach (readdir $dh) {
		my $fn = "$dn/$_";
		my $fn_bn_lc = lc($_);

		if ($fn_bn_lc =~ /.flac$/ and -f $fn) {
			$files{$fn} = { gettags($fn) };
		}

		if ($fn_bn_lc =~ /.log$/ and -f $fn) {
			my $log_tmp = check_log($fn);

			if (defined($log_tmp)) { push(@log, $fn); }
		}
	}
	closedir $dh or die "Can't close directory '$dn': $!";

	return(@log);
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

# This subroutine checks the log file to see if it contains any of the
# words in @lacc. Most of the code here is to deal with correctly
# decoding the character encoding in the log file. We do this to be able
# to properly match the words.
sub check_log {
	my $fn = shift;
	my($enc, $line1);

	open(OUTPUT, '-|', 'file', '-i', $fn) or die "Can't run file: $!";
	chomp(my $file_output = <OUTPUT>);
	close(OUTPUT) or die "Can't close file: $!";

	$file_output =~ /charset=(.*)[[:space:]]*$/;
	my $file_enc = $1;

	my $enc_tmp = find_encoding($file_enc);

	if (defined($enc_tmp)) { $enc = $enc_tmp->name; }

	open(my $text, '<', $fn) or die "Can't open file '$fn': $!";
	$line1 = <$text>;
	$line1 =~ s/(\r){0,}(\n){0,}$//g;
	if (defined($enc)) { $line1 = decode($enc, $line1); }
	close $text or die "Can't close file '$fn': $!";

	foreach my $req (@lacc) {
	    if ($line1 =~ /$req/) { return($fn); }
	}
}

sub import {
	my $fc = shift;
	my $cp = 0;
	my $cplog = 1;
	my $total = $fc;
	my ($newfn, $path);

	foreach my $sf (sort(keys %files)) {
		undef(%t);

		foreach my $tag (keys( %{ $files{$sf} } )) {
			$t{$tag} = $files{$sf}{$tag}->[0];
		}
		checktags($sf);
		albumartist($sf, $fc);

		my %ct = ( albumartist => $t{albumartist}, album => $t{album},
		discnumber => $t{discnumber}, tracknumber => $t{tracknumber},
		title => $t{title} );

		$path = $library . '/' . $ct{albumartist} . '/' . $ct{album};

		if ($cp == 0 and -d $path) {
			say $path . ': already exists';
			say 'Skipping...' . "\n";
			return;
		} else { make_path($path); }

		if (defined($t{discnumber})) {
		  $newfn = sprintf('%s-%02s. %s.flac', $ct{discnumber}, $ct{tracknumber}, $ct{title});
		} else {
		  $newfn = sprintf('%02s. %s.flac', $ct{tracknumber}, $ct{title});
		}

		my $tf = $path . '/' . $newfn;

		say 'Copying \'' . $sf . '\'' . "\n\t" . 'to \'' . $tf . '\'...';
		copy($sf, $tf) or die "Copy failed: $!";
		$cp++
	}

	say 'Copied ' . $cp . ' / ' . $total . ' files from \'' . $t{album} . '\'.' . "\n";

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
