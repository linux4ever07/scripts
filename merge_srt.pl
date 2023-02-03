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
use File::Basename qw(basename);
use Cwd qw(abs_path cwd);
use Encode qw(encode decode find_encoding);

my($dn, $of, $delim, $offset, $n);
my(@files, @lines, @format);

my $regex_ext = qr/\.([^.]*)$/;

$offset = 0;
$n = 0;

$dn = cwd();
$of = $dn . '/' . 'merged_srt' . '-' . int(rand(10000)) . '-' . int(rand(10000)) . '.srt';

if (! scalar(@ARGV)) { usage(); }

while (my $arg = shift(@ARGV)) {
	my($fn, $ext);

	if (length($arg)) {
		$fn = abs_path($arg);
		$fn =~ /$regex_ext/;
		$ext = lc($1);
	}

	if (! -f $fn or $ext ne 'srt') { usage(); }

	push(@files, $fn);
}

$delim = ' --> ';

$format[0] = qr/[0-9]+/;
$format[1] = qr/([0-9]{2}):([0-9]{2}):([0-9]{2}),([0-9]{3})/;
$format[2] = qr/[0-9]{2}:[0-9]{2}:[0-9]{2},[0-9]{3}/;
$format[3] = qr/^($format[2])$delim($format[2])$/;

# The 'usage' subroutine prints syntax, and then quits.
sub usage {
	say "\n" . 'Usage: ' . basename($0) . ' [srt...]' . "\n";
	exit;
}

# The 'read_decode_fn' subroutine reads a text file and encodes the
# output to UTF-8.
sub read_decode_fn {
	my $fn = shift;
	my($file_output, $file_enc, $enc, $enc_tmp, @lines);

	open(my $info, '-|', 'file', '-i', $fn) or die "Can't run file: $!";
	chomp($file_output = <$info>);
	close($info) or die "Can't close file: $!";

	$file_output =~ /charset=(.*)[[:space:]]*$/;
	$file_enc = $1;

	$enc_tmp = find_encoding($file_enc);

	if (length($enc_tmp)) { $enc = $enc_tmp->name; }

	open(my $text, '< :raw', $fn) or die "Can't open file '$fn': $!";
	foreach my $line (<$text>) {
		if (length($enc)) {
			$line = decode($enc, $line);
			$line = encode("utf8", $line);
		}

		$line =~ s/(\r){0,}(\n){0,}$//g;
		push(@lines, $line);
	}
	close $text or die "Can't close file '$fn': $!";

	return(@lines);
}

# The 'time_convert' subroutine converts the 'time line' back and forth
# between the time (hh:mm:ss) format and centiseconds.
sub time_convert {
	my $time = shift;

	my $h = 0;
	my $m = 0;
	my $s = 0;
	my $cs = 0;

# If argument is in the hh:mm:ss format...
	if ($time =~ /$format[1]/) {
		$h = $1;
		$m = $2;
		$s = $3;
		$cs = $4;

		$h =~ s/^0//;
		$m =~ s/^0//;
		$s =~ s/^0//;
		$cs =~ s/^0{1,2}//;

# Converts all the numbers to centiseconds, because those kind of values
# will be easier to compare in the 'time_calc' subroutine.
		$h = $h * 60 * 60 * 1000;
		$m = $m * 60 * 1000;
		$s = $s * 1000;

		$time = $h + $m + $s + $cs;

# If argument is in the centisecond format...
	} elsif ($time =~ /$format[0]/) {
		$cs = $time;

# While $cs (centiseconds) is equal to (or greater than) 1000, clear the
# $cs variable and add 1 to the $s (seconds) variable.
		while ($cs >= 1000) {
			$s = $s + 1;
			$cs = $cs - 1000;
		}

# While $s (seconds) is equal to (or greater than) 60, clear the $s
# variable and add 1 to the $m (minutes) variable.
		while ($s >= 60) {
			$m = $m + 1;
			$s = $s - 60;
		}

# While $m (minutes) is equal to (or greater than) 60, clear the $m
# variable and add 1 to the $h (hours) variable.
		while ($m >= 60) {
			$h = $h + 1;
			$m = $m - 60;
		}

# While $h (hours) is equal to 100 (or greater than), clear the $h
# variable.
		while ($h >= 100) {
			$h = $h - 100;
		}

		$time = sprintf('%02d:%02d:%02d,%03d', $h, $m, $s, $cs);
	}

	return($time);
}

# The 'time_calc' subroutine adds the total time of the previous SRT
# subtitle file to the current 'time line'.
sub time_calc {
	my $start_time = shift;
	my $stop_time = shift;

	my($diff);
	my(@times);

	$start_time = time_convert($start_time);
	$stop_time = time_convert($stop_time);

	if ($offset > 0 and $start_time < 100) {
		$diff = 100 - $start_time;

		$start_time = $start_time + $diff;
		$stop_time = $stop_time + $diff;
	}

	$start_time = $offset + $start_time;
	$stop_time = $offset + $stop_time;

	$start_time = time_convert($start_time);
	$stop_time = time_convert($stop_time);

	push(@times, $start_time, $stop_time);

	return(@times);
}

# The 'parse_srt' subroutine reads the SRT subtitle file passed to it,
# and adjusts the timestamps.
sub parse_srt {
	my $fn = shift;
	my $i = 0;
	my $j = 0;
	my $switch = 0;
	my($this, $next, $end, $start_time, $stop_time, $time_line);
	my(@lines, @lines_tmp);

	push(@lines_tmp, read_decode_fn($fn));

	$end = $#lines_tmp;

	until ($i > $end) {
		$j = $i + 1;

		$this = $lines_tmp[$i];
		$next = $lines_tmp[$j];

		if (length($this) and $this =~ /$format[0]/) {
			if (length($next) and $next =~ /$format[3]/) {
				$start_time = $1;
				$stop_time = $2;

				my(@times, @tmp);

				if ($offset > 0) {
					push(@times, time_calc($start_time, $stop_time));
					$time_line = $times[0] . $delim . $times[1];
				} else { $time_line = $next; }

				push(@tmp, $time_line);

				$i = $i + 2;
				$j = $i + 1;

				$this = $lines_tmp[$i];
				$next = $lines_tmp[$j];

				if (length($this)) { push(@tmp, $this); }

				until ($i > $end) {
					$i = $i + 1;
					$j = $i + 1;

					$this = $lines_tmp[$i];
					$next = $lines_tmp[$j];

					if (length($this) and $this =~ /$format[0]/) {
						if (length($next) and $next =~ /$format[3]/) {
							$switch = 1;
							last;
						}
					}

					if (length($this)) { push(@tmp, $this); }
				}

				if (scalar(@tmp) > 0) {
					$n = $n + 1;

					push(@lines, $n);

					foreach my $line (@tmp) {
						push(@lines, $line);
					}

					if (scalar(@tmp) == 1) { push(@lines, '', ''); }
					else { push(@lines, ''); }
				}

				undef(@times);
				undef(@tmp);
			}
		}

		if ($switch eq 0) { $i = $i + 1; }
		else { $switch = 0; }
	}

	$offset = $offset + time_convert($stop_time);

	return(@lines);
}

while (my $fn = shift(@files)) {
	push(@lines, parse_srt($fn));
}

open(my $srt, '> :raw', $of) or die "Can't open file '$of': $!";
while (my $line = shift(@lines)) {
	print $srt $line . "\r\n";
}
close($srt) or die "Can't close file '$of': $!";

say "\n" . 'Wrote file: ' . $of . "\n";
