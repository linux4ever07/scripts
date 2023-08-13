#!/usr/bin/perl

# This script merges an arbitrary number of SRT subtitle files to 1
# file, and adjusts the timings. This is useful when a movie that's
# split accross multiple discs has been merged to 1 file, and the
# subtitles also need to be merged. Or just merging SRT subtitle files
# in general.

# The charset of the input files will be decoded and then encoded to
# UTF-8 in the output file.

# The output file will probably still need to be edited in a subtitle
# editor to be properly synced to the movie file, but at least most of
# the work will already be done.

use 5.34.0;
use strict;
use warnings;
use diagnostics;
use File::Basename qw(basename);
use Cwd qw(abs_path cwd);
use Encode qw(encode decode find_encoding);
use POSIX qw(floor);

my(%regex, %lines);
my(@files, @lines_tmp, @lines, @format, @offset);
my($dn, $of, $delim, $n, $total_n);

$regex{fn} = qr/^(.*)\.([^.]*)$/;
$regex{charset1} = qr/([^; ]+)$/;
$regex{charset2} = qr/^charset=(.*)$/;
$regex{newline} = qr/(\r){0,}(\n){0,}$/;
$regex{blank1} = qr/^[[:blank:]]*(.*)[[:blank:]]*$/;
$regex{blank2} = qr/^[[:blank:]]*$/;
$regex{blank3} = qr/ +/;
$regex{zero} = qr/^0+([0-9]+)$/;

@offset = (0, 0);

$dn = cwd();
$of = $dn . '/' . 'merged_srt' . '-' . int(rand(10000)) . '-' . int(rand(10000)) . '.srt';

if (! scalar(@ARGV)) { usage(); }

while (my $arg = shift(@ARGV)) {
	my($fn, $ext);

	if (! length($arg)) { next; }

	$fn = abs_path($arg);
	$fn =~ m/$regex{fn}/;
	$ext = lc($2);

	if (! -f $fn or $ext ne 'srt') { usage(); }

	push(@files, $fn);
}

if (! scalar(@files)) { usage(); }

$delim = '-->';

$format[0] = qr/[0-9]+/;
$format[1] = qr/([0-9]{2}):([0-9]{2}):([0-9]{2}),([0-9]{3})/;
$format[2] = qr/[0-9]{2}:[0-9]{2}:[0-9]{2},[0-9]{3}/;
$format[3] = qr/^($format[2]) *$delim *($format[2])$/;
$format[4] = qr/^\{([0-9]+)\}\{([0-9]+)\}(.*)$/;

# The 'usage' subroutine prints syntax, and then quits.
sub usage {
	say "\n" . 'Usage: ' . basename($0) . ' [srt...]' . "\n";
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
	my($i, $this);

	$i = 0;

	until ($i == scalar(@lines_tmp)) {
		$this = $lines_tmp[$i];

		if (length($this) and ! $this =~ m/$format[4]/) {
			return;
		}

		$i += 1;
	}

	$i = 0;

	until ($i == scalar(@lines_tmp)) {
		$this = $lines_tmp[$i];

		if (length($this) and $this =~ m/$format[4]/) {
			$n += 1;

			$lines{$n}{start} = frames2ms($1);
			$lines{$n}{stop} = frames2ms($2);

			push(@{$lines{$n}{text}}, split('\|', $3));
		}

		$i += 1;
	}

	$total_n = $n;
	$n = 0;

	until ($n == $total_n) {
		$n += 1;

		if (! length($lines{$n}{text})) { next; }

		for ($i = 0; $i < scalar(@{$lines{$n}{text}}); $i++) {
			$lines{$n}{text}->[$i] =~ s/$regex{blank1}/$1/;
		}
	}
}

# The 'parse_srt_good' parses a subtitle in the correct SRT (SubRip)
# format.
sub parse_srt_good {
	my($i, $j, $this, $next);

	$i = 0;
	$j = 0;

	until ($i == scalar(@lines_tmp)) {
		$j = $i + 1;

		$this = $lines_tmp[$i];
		$next = $lines_tmp[$j];

		if (length($this) and $this =~ m/$format[0]/) {
			if (length($next) and $next =~ m/$format[3]/) {
				$n += 1;

				$lines{$n}{start} = time_convert($1);
				$lines{$n}{stop} = time_convert($2);

				$i += 2;

				$this = $lines_tmp[$i];
			}
		}

		if (length($this)) {
			push(@{$lines{$n}{text}}, $this);
		}

		$i += 1;
	}

	$total_n = $n;
}

# The 'time_calc' subroutine adds the total time of the previous SRT
# subtitle file to the current 'time line'.
sub time_calc {
	my $start_time = shift;
	my $stop_time = shift;

	my($diff);

	if ($offset[1] == 0) {
		return($start_time, $stop_time);
	}

	if ($start_time < 100) {
		$diff = 100 - $start_time;

		$start_time = $start_time + $diff;
		$stop_time = $stop_time + $diff;
	}

	$start_time = $offset[1] + $start_time;
	$stop_time = $offset[1] + $stop_time;

	return($start_time, $stop_time);
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

	$n = 0;

	@lines_tmp = ();

	until ($n == $total_n) {
		$n += 1;

		$start_time = $lines{$n}{start};
		$stop_time = $lines{$n}{stop};

		($start_time, $stop_time) = time_calc($start_time, $stop_time);

		$start_time = time_convert($start_time);
		$stop_time = time_convert($stop_time);

		$time_line = $start_time . ' ' . $delim . ' ' . $stop_time;

		push(@lines_tmp, $n + $offset[0], $time_line);

		foreach my $line (@{$lines{$n}{text}}) {
			push(@lines_tmp, $line);
		}

		push(@lines_tmp, '');
	}

	$offset[0] += $n;
	$offset[1] += time_convert($stop_time);
}

while (my $fn = shift(@files)) {
	process_sub($fn);

	push(@lines, @lines_tmp);
}

open(my $srt, '> :raw', $of) or die "Can't open file '$of': $!";
foreach my $line (@lines) {
	print $srt $line . "\r\n";
}
close($srt) or die "Can't close file '$of': $!";

say "\n" . 'Wrote file: ' . $of . "\n";
