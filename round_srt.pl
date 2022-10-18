#!/usr/bin/perl

# This script will round all the centiseconds in an SRT subtitle file.
# Every start time and end time of a subtitle will now end in ,?00

# Example: 00:20:47,500 --> 00:20:52,600
# Instead of: 00:20:47,457 --> 00:20:52,611

# This makes it a lot easier to edit the subtitle in for example Gnome
# Subtitles, if needed. Even if you're not going to edit the subtitle
# afterwards, it just looks better using whole centiseconds. The output
# filename is the same as the input filename, only a random number is
# added to the name. The start and end times of every subtitle line are
# adjusted so they don't overlap. They will all differ by at least 1
# centisecond.

use 5.34.0;
use strict;
use warnings;
use File::Basename qw(basename);
use Cwd qw(abs_path cwd);
use Encode qw(encode decode find_encoding);

my $script = basename($0);

my($delim);
my(@files, @format);

my $regex_ext = qr/\.([^.]*)$/;

if (scalar(@ARGV) == 0) { usage(); }

foreach my $arg (@ARGV) {
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
	say 'Usage: ' . $script . ' [srt...]' . "\n";
	exit;
}

# The 'read_decode_fn' subroutine reads a text file and encodes the
# output to UTF-8.
sub read_decode_fn {
	my $fn = shift;
	my($enc);
	my(@lines);

	open(my $info, '-|', 'file', '-i', $fn) or die "Can't run file: $!";
	chomp(my $file_output = <$info>);
	close($info) or die "Can't close file: $!";

	$file_output =~ /charset=(.*)[[:space:]]*$/;
	my $file_enc = $1;

	my $enc_tmp = find_encoding($file_enc);

	if (defined($enc_tmp)) { $enc = $enc_tmp->name; }

	open(my $text, '< :raw', $fn) or die "Can't open file '$fn': $!";
	foreach my $line (<$text>) {
		if (defined($enc)) {
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

	my $regex_last2 = qr/^.*(..)$/;

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

# Saves the last 2 (or 1) digits of $cs in $cs_tmp.
		my($cs_tmp);

		if ($cs =~ $regex_last2) {
			$cs_tmp = $1;
			$cs_tmp =~ s/^0//;
		}

		if (! length($cs_tmp)) { $cs_tmp = 0; }

# If $cs_tmp is greater than 50, round it up, and if not, round it down.
		if ($cs_tmp >= 50) { $cs = ($cs - $cs_tmp) + 100; }
		else { $cs = $cs - $cs_tmp; }

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

# The 'time_calc' subroutine adds the total time of the previous
# 'time line' to the current 'time line', plus a centisecond if
# centiseconds are identical with previous 'time line'.
sub time_calc {
	my $start_time = shift;
	my $stop_time = shift;

# Until the value of the current 'time_line' is higher than the
# previous, add 1 centisecond.
	until ($start_time > $stop_time) {
		$start_time = $start_time + 100;
	}

	return($start_time);
}

# The 'parse_srt' subroutine reads the SRT subtitle file passed to it,
# and adjusts the timestamps.
sub parse_srt {
	my $fn = shift;
	my $i = 0;
	my $j = 0;
	my $n = 0;
	my $switch = 0;
	my($this, $next, $end, $start_time, $stop_time, $time_line, $previous);
	my(@lines, @lines_tmp);

	push(@lines_tmp, read_decode_fn($fn));

	$end = $#lines_tmp - 1;

	until ($i >= $end) {
		$j = $i + 1;

		$this = $lines_tmp[$i];
		$next = $lines_tmp[$j];

		if (length($this) and $this =~ /$format[0]/) {
			if (length($next) and $next =~ /$format[3]/) {
				$start_time = $1;
				$stop_time = $2;

				my(@tmp);

				$start_time = time_convert($start_time);
				$stop_time = time_convert($stop_time);

				if (length($previous)) {
					$start_time = time_calc($start_time, $previous);
				}

				$previous = $stop_time;

				$start_time = time_convert($start_time);
				$stop_time = time_convert($stop_time);

				$time_line = $start_time . $delim . $stop_time;

				push(@tmp, $time_line);

				$i = $i + 2;
				$j = $i + 1;

				$this = $lines_tmp[$i];
				$next = $lines_tmp[$j];

				if (length($this)) { push(@tmp, $this); }

				until ($i >= $end) {
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

				undef(@tmp);
			}
		}

		if ($switch eq 0) { $i = $i + 1; }
		else { $switch = 0; }
	}

	return(@lines);
}

foreach my $fn (@files) {
	my $of = $fn;
	$of =~ s/$regex_ext//;
	$of = $of . '-' . int(rand(10000)) . '-' . int(rand(10000)) . '.srt';

	my(@lines);

	push(@lines, parse_srt($fn));

	open(my $srt, '> :raw', $of) or die "Can't open file '$of': $!";
	foreach my $line (@lines) {
		print $srt $line . "\r\n";
	}
	close($srt) or die "Can't close file '$of': $!";

	undef(@lines);

	say "\n" . 'Wrote file: ' . $of . "\n";
}
