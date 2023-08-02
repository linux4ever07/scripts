#!/usr/bin/perl

# This script will shift the timestamps in an SRT subtitle file, by the
# amount specified as the 1st argument. Specifically, it shifts the last
# timestamp by the full amount, and every other timestamp between the
# 1st and last by the approriate amount to make them all line up
# proportionally.

# Example:

# adjust_srt.pl '+00:00:03,000' 'subtitle.srt'

use 5.34.0;
use strict;
use warnings;
use diagnostics;
use File::Basename qw(basename);
use Cwd qw(abs_path);
use Encode qw(encode decode find_encoding);
use POSIX qw(floor);

my(%regex, @files, @format, @interval);
my($delim, $mode, $shift, $n, $total_n, $offset, $threshold);

$regex{fn} = qr/^(.*)\.([^.]*)$/;
$regex{charset1} = qr/([^; ]+)$/;
$regex{charset2} = qr/^charset=(.*)$/;
$regex{newline} = qr/(\r){0,}(\n){0,}$/;
$regex{blank1} = qr/^[[:blank:]]*(.*)[[:blank:]]*$/;
$regex{blank2} = qr/^[[:blank:]]*$/;
$regex{blank3} = qr/[[:blank:]]+/;
$regex{last2} = qr/([0-9]{1,2})$/;
$regex{zero} = qr/^0+([0-9]+)$/;

$delim = ' --> ';

$format[0] = qr/[0-9]+/;
$format[1] = qr/([0-9]{2}):([0-9]{2}):([0-9]{2}),([0-9]{3})/;
$format[2] = qr/[0-9]{2}:[0-9]{2}:[0-9]{2},[0-9]{3}/;
$format[3] = qr/^($format[2])$delim($format[2])$/;
$format[4] = qr/^([-+])($format[2])$/;

@interval = (0, 0);

$n = 0;
$total_n = 0;
$offset = 0;
$threshold = 2;

if (! scalar(@ARGV)) { usage(); }

$mode = shift(@ARGV);

if ($mode =~ m/$format[4]/) {
	$mode = $1;
	$shift = time_convert($2);
} else { usage(); }

if ($mode eq '-') { $mode = 0; }
if ($mode eq '+') { $mode = 1; }

while (my $arg = shift(@ARGV)) {
	my($fn, $ext);

	if (length($arg)) {
		$fn = abs_path($arg);
		$fn =~ m/$regex{fn}/;
		$ext = lc($2);
	}

	if (! -f $fn or $ext ne 'srt') { usage(); }

	push(@files, $fn);
}

if (! scalar(@files)) {
	usage();
}

# The 'usage' subroutine prints syntax, and then quits.
sub usage {
	say "\n" . 'Usage: ' . basename($0) . ' [-+][h{2}:m{2}:s{2},ms{3}] [srt...]' . "\n";
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
# between the time (hh:mm:ss) format and centiseconds.
sub time_convert {
	my $time = shift;

	my $h = 0;
	my $m = 0;
	my $s = 0;
	my $cs = 0;

	my $cs_last = 0;

# If argument is in the hh:mm:ss format...
	if ($time =~ m/$format[1]/) {
		$h = $1;
		$m = $2;
		$s = $3;
		$cs = $4;

		$h =~ s/$regex{zero}/$1/;
		$m =~ s/$regex{zero}/$1/;
		$s =~ s/$regex{zero}/$1/;
		$cs =~ s/$regex{zero}/$1/;

# Converts all the numbers to centiseconds, because those kind of values
# will be easier to compare in the 'time_calc' subroutine.
		$h = $h * 60 * 60 * 1000;
		$m = $m * 60 * 1000;
		$s = $s * 1000;

		$time = $h + $m + $s + $cs;

# If argument is in the centisecond format...
	} elsif ($time =~ m/$format[0]/) {
		$cs = $time;

		$s = floor($cs / 1000);
		$m = floor($s / 60);
		$h = floor($m / 60);

		$cs = floor($cs % 1000);
		$s = floor($s % 60);
		$m = floor($m % 60);

		$time = sprintf('%02d:%02d:%02d,%03d', $h, $m, $s, $cs);
	}

	return($time);
}

# The 'time_calc' subroutine shifts the current 'time line' according
# to the amount specified when running the script.
sub time_calc {
	my $start_time = shift;
	my $stop_time = shift;

	if ($n < $threshold) {
		return($start_time, $stop_time);
	}

	if ($n == $total_n) {
		$offset = $offset + $interval[1];
	} else {
		$offset = $offset + $interval[0];
	}

	if ($mode == 1) {
		$start_time = $start_time + $offset;
		$stop_time = $stop_time + $offset;
	}

	if ($mode == 0) {
		$start_time = $start_time - $offset;
		$stop_time = $stop_time - $offset;
	}

	return($start_time, $stop_time);
}

# The 'parse_srt' subroutine reads the SRT subtitle file passed to it,
# and adjusts the timestamps.
sub parse_srt {
	my $fn = shift;

	my($this, $next, $end);
	my($start_time, $stop_time, $time_line);
	my(%lines, @lines_tmp);

	my $i = 0;
	my $j = 0;
	my $switch = 0;

	push(@lines_tmp, read_decode_fn($fn));

	$end = $#lines_tmp;

	until ($i > $end) {
		$j = $i + 1;

		$this = $lines_tmp[$i];
		$next = $lines_tmp[$j];

		if (length($this) and $this =~ m/$format[0]/) {
			if (length($next) and $next =~ m/$format[3]/) {
				$start_time = time_convert($1);
				$stop_time = time_convert($2);

				$n = $n + 1;

				$lines{$n}{start} = $start_time;
				$lines{$n}{stop} = $stop_time;

				$i = $i + 2;
				$j = $i + 1;

				$this = $lines_tmp[$i];
				$next = $lines_tmp[$j];

				if (length($this)) {
					push(@{$lines{$n}{text}}, $this);
				}

				until ($i > $end) {
					$i = $i + 1;
					$j = $i + 1;

					$this = $lines_tmp[$i];
					$next = $lines_tmp[$j];

					if (length($this) and $this =~ m/$format[0]/) {
						if (length($next) and $next =~ m/$format[3]/) {
							$switch = 1;
							last;
						}
					}

					if (length($this)) {
						push(@{$lines{$n}{text}}, $this);
					}
				}
			}
		}

		if ($switch eq 0) { $i = $i + 1; }
		else { $switch = 0; }
	}

	$total_n = $n;

	if ($n > 2) { $n = $n - 2; }

	$interval[0] = floor($shift / $n);
	$interval[1] = floor($shift % $n);

	if ($n > $shift) {
		@interval = (1, 1);
		$threshold = ($n - $shift) + 3;
	}

	$n = 1;

	@lines_tmp = ();

	until ($n > $total_n) {
		$start_time = $lines{$n}{start};
		$stop_time = $lines{$n}{stop};

		($start_time, $stop_time) = time_calc($start_time, $stop_time);

		$start_time = time_convert($start_time);
		$stop_time = time_convert($stop_time);

		$time_line = $start_time . $delim . $stop_time;

		push(@lines_tmp, $n, $time_line);

		foreach my $line (@{$lines{$n}{text}}) {
			push(@lines_tmp, $line);
		}

		push(@lines_tmp, '');

		$n = $n + 1;
	}

	return(@lines_tmp);
}

while (my $fn = shift(@files)) {
	my $of = $fn;
	$of =~ s/$regex{fn}/$1/;
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