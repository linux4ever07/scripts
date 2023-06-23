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
use POSIX qw(floor);

my($dn, $of, $delim, $offset, $n);
my(%regex, @files, @lines, @format);

$regex{fn} = qr/^(.*)\.([^.]*)$/;
$regex{charset1} = qr/([^; ]+)$/;
$regex{charset2} = qr/^charset=(.*)$/;
$regex{blank1} = qr/^[[:blank:]]*(.*)[[:blank:]]*$/;
$regex{blank2} = qr/[[:blank:]]+/;

$offset = 0;
$n = 0;

$dn = cwd();
$of = $dn . '/' . 'merged_srt' . '-' . int(rand(10000)) . '-' . int(rand(10000)) . '.srt';

if (! scalar(@ARGV)) { usage(); }

while (my $arg = shift(@ARGV)) {
	my($fn, $ext);

	if (length($arg)) {
		$fn = abs_path($arg);
		$fn =~ /$regex{fn}/;
		$ext = lc($2);
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
	my($file_enc, $tmp_enc, $enc, @lines);

	open(my $info, '-|', 'file', '-bi', $fn) or die "Can't run file: $!";
	chomp($file_enc = <$info>);
	close($info) or die "Can't close file: $!";

	$file_enc =~ /$regex{charset1}/;
	$file_enc = $1;
	$file_enc =~ /$regex{charset2}/;
	$file_enc = $1;

	$tmp_enc = find_encoding($file_enc);

	if (length($tmp_enc)) { $enc = $tmp_enc->name; }

	open(my $text, '< :raw', $fn) or die "Can't open file '$fn': $!";
	foreach my $line (<$text>) {
		if (length($enc)) {
			$line = decode($enc, $line);
			$line = encode("utf8", $line);
		}

		$line =~ s/(\r){0,}(\n){0,}$//g;

		$line =~ s/$regex{blank1}/$1/;
		$line =~ s/$regex{blank2}/ /g;

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
foreach my $line (@lines) {
	print $srt $line . "\r\n";
}
close($srt) or die "Can't close file '$of': $!";

say "\n" . 'Wrote file: ' . $of . "\n";
