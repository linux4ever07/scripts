#!/usr/bin/perl

# This script simply parses an SRT (SubRip) subtitle file, and prints
# the content without the timestamps.

use 5.34.0;
use strict;
use warnings;
use diagnostics;
use File::Basename qw(basename);
use Cwd qw(abs_path);
use Encode qw(encode decode find_encoding);
use POSIX qw(floor);

my(%regex, %lines);
my(@lines_tmp, @format);
my($delim, $n, $total_n, $fn, $ext);

$regex{fn} = qr/^(.*)\.([^.]*)$/;
$regex{charset1} = qr/([^; ]+)$/;
$regex{charset2} = qr/^charset=(.*)$/;
$regex{newline} = qr/(\r){0,}(\n){0,}$/;
$regex{blank1} = qr/^[[:blank:]]*(.*)[[:blank:]]*$/;
$regex{blank2} = qr/^[[:blank:]]*$/;
$regex{blank3} = qr/[[:blank:]]+/;
$regex{zero} = qr/^0+([0-9]+)$/;

if (! scalar(@ARGV)) { usage(); }

if (length($ARGV[0])) {
	$fn = abs_path($ARGV[0]);
	$fn =~ m/$regex{fn}/;
	$ext = lc($2);
}

if (! -f $fn or $ext ne 'srt') { usage(); }

$delim = '-->';

$format[0] = qr/[0-9]+/;
$format[1] = qr/([0-9]{2}):([0-9]{2}):([0-9]{2}),([0-9]{3})/;
$format[2] = qr/[0-9]{2}:[0-9]{2}:[0-9]{2},[0-9]{3}/;
$format[3] = qr/^($format[2]) *$delim *($format[2])$/;
$format[4] = qr/^\{([0-9]+)\}\{([0-9]+)\}(.*)$/;

# The 'usage' subroutine prints syntax, and then quits.
sub usage {
	say "\n" . 'Usage: ' . basename($0) . ' [srt]' . "\n";
	exit;
}

# The 'read_decode_fn' subroutine reads a text file and encodes the
# output to UTF-8.
sub read_decode_fn {
	my $fn = shift;
	my($file_enc, $tmp_enc, $enc, @lines);

	open(my $info, '-|', 'file', '-bi', $fn) or die "Can't run file: $!";
	chomp($file_enc = <$info>);
	close($info) or die "Can't close file: $!";

	$file_enc =~ m/$regex{charset1}/;
	$file_enc = $1;
	$file_enc =~ m/$regex{charset2}/;
	$file_enc = $1;

	$tmp_enc = find_encoding($file_enc);

	if (length($tmp_enc)) { $enc = $tmp_enc->name; }

	open(my $text, '< :raw', $fn) or die "Can't open file '$fn': $!";
	foreach my $line (<$text>) {
		if (length($enc)) {
			$line = decode($enc, $line);
			$line = encode('utf8', $line);
		}

		$line =~ s/$regex{newline}//g;

		$line =~ s/$regex{blank1}/$1/;
		$line =~ s/$regex{blank2}//;
		$line =~ s/$regex{blank3}/ /g;

		push(@lines, $line);
	}
	close $text or die "Can't close file '$fn': $!";

	return(@lines);
}

# The 'time_convert' subroutine converts the 'time line' back and forth
# between the time (hh:mm:ss) format and milliseconds.
sub time_convert {
	my $time = shift;

	my $h = 0;
	my $m = 0;
	my $s = 0;
	my $ms = 0;

# If argument is in the hh:mm:ss format...
	if ($time =~ m/$format[1]/) {
		$h = $1;
		$m = $2;
		$s = $3;
		$ms = $4;

		$h =~ s/$regex{zero}/$1/;
		$m =~ s/$regex{zero}/$1/;
		$s =~ s/$regex{zero}/$1/;
		$ms =~ s/$regex{zero}/$1/;

# Converts all the numbers to milliseconds, because that kind of
# value is easier to process.
		$h = $h * 60 * 60 * 1000;
		$m = $m * 60 * 1000;
		$s = $s * 1000;

		$time = $h + $m + $s + $ms;

# If argument is in the millisecond format...
	} elsif ($time =~ m/$format[0]/) {
		$ms = $time;

		$s = floor($ms / 1000);
		$m = floor($s / 60);
		$h = floor($m / 60);

		$ms = floor($ms % 1000);
		$s = floor($s % 60);
		$m = floor($m % 60);

		$time = sprintf('%02d:%02d:%02d,%03d', $h, $m, $s, $ms);
	}

	return($time);
}

# The 'frames2ms' subroutine converts video frames to milliseconds.
# 24 frames per second is the standard for movies.
sub frames2ms {
	my $frames = shift;

	my $ms = floor(($frames / 24) * 1000);

	return($ms);
}

# The 'parse_srt_bad' parses a subtitle that has the SRT extension, but
# is not in the correct (SubRip) format. It's another semi-common
# format.
sub parse_srt_bad {
	my($i, $this, $end);
	my($start_time, $stop_time);

	$i = 0;

	$end = $#lines_tmp;

	until ($i > $end) {
		$this = $lines_tmp[$i];

		if (! $this =~ m/$format[4]/) {
			return;
		}

		$i += 1;
	}

	$i = 0;

	until ($i > $end) {
		$this = $lines_tmp[$i];

		if ($this =~ m/$format[4]/) {
			$n += 1;

			$lines{$n}{start} = frames2ms($1);
			$lines{$n}{stop} = frames2ms($2);

			push(@{$lines{$n}{text}}, split('\|', $3));
		}

		$i += 1;
	}
}

# The 'parse_srt_good' parses a subtitle in the correct SRT (SubRip)
# format.
sub parse_srt_good {
	my($i, $j, $this, $next, $end);
	my($start_time, $stop_time);

	$i = 0;
	$j = 0;

	$end = $#lines_tmp;

	until ($i > $end) {
		$j = $i + 1;

		$this = $lines_tmp[$i];
		$next = $lines_tmp[$j];

		if (length($this) and $this =~ m/$format[0]/) {
			if (length($next) and $next =~ m/$format[3]/) {
				$start_time = time_convert($1);
				$stop_time = time_convert($2);

				$n += 1;

				$lines{$n}{start} = $start_time;
				$lines{$n}{stop} = $stop_time;

				$i += 2;

				$this = $lines_tmp[$i];
			}
		}

		if (length($this)) {
			push(@{$lines{$n}{text}}, $this);
		}

		$i += 1;
	}
}

# The 'process_sub' subroutine reads a subtitle file, parses and
# processes it, and then prints the result.
sub process_sub {
	my $fn = shift;

	my($start_time, $stop_time, $time_line);

	$n = 0;
	$total_n = 0;

	@lines_tmp = ();
	%lines = ();

	push(@lines_tmp, read_decode_fn($fn));

	parse_srt_bad();

	if ($n == 0) {
		parse_srt_good();
	}

	$total_n = $n;
	$n = 0;

	@lines_tmp = ();

	until ($n == $total_n) {
		$n += 1;

		foreach my $line (@{$lines{$n}{text}}) {
			push(@lines_tmp, $n . ': ' . $line);
		}

		push(@lines_tmp, '');
	}
}

process_sub($fn);

say $fn . "\n";

foreach my $line (@lines_tmp) {
	say $line;
}
