#!/usr/bin/perl

# This script will round all the centiseconds in an SRT (SubRip)
# subtitle file. Every start time and end time of a subtitle will now
# end in ,?00

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
use diagnostics;
use File::Basename qw(basename);
use Cwd qw(abs_path);
use Encode qw(encode decode find_encoding);
use POSIX qw(floor);

my(%regex, %lines);
my(@files, @lines_tmp, @format);
my($delim, $n, $total_n);

$regex{fn} = qr/^(.*)\.([^.]*)$/;
$regex{charset1} = qr/([^; ]+)$/;
$regex{charset2} = qr/^charset=(.*)$/;
$regex{newline} = qr/(\r){0,}(\n){0,}$/;
$regex{blank1} = qr/^[[:blank:]]*(.*)[[:blank:]]*$/;
$regex{blank2} = qr/^[[:blank:]]*$/;
$regex{blank3} = qr/[[:blank:]]+/;
$regex{last2} = qr/([0-9]{1,2})$/;
$regex{zero} = qr/^0+([0-9]+)$/;

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

		$ms = round_ms($ms);

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

	$ms = round_ms($ms);

	return($ms);
}

# The 'round_ms' subroutine rounds millisecond values to the closest
# centisecond.
sub round_ms {
	my $ms = shift;

	my $ms_last = 0;

# Saves the last 2 (or 1) digits of $ms in $ms_last.
	if ($ms =~ m/$regex{last2}/) {
		$ms_last = $1;
		$ms_last =~ s/$regex{zero}/$1/;
	}

# If $ms_last is greater than 50, round it up, and if not, round it
# down.
	if ($ms_last >= 50) { $ms = ($ms - $ms_last) + 100; }
	else { $ms = $ms - $ms_last; }

	return($ms);
}

# The 'parse_srt_bad' parses a subtitle that has the SRT extension, but
# is not in the correct (SubRip) format. It's another semi-common
# format.
sub parse_srt_bad {
	my($i, $this, $end);

	$i = 0;

	$end = $#lines_tmp;

	until ($i > $end) {
		$this = $lines_tmp[$i];

		if (length($this) and ! $this =~ m/$format[4]/) {
			return;
		}

		$i += 1;
	}

	$i = 0;

	until ($i > $end) {
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
	my($i, $j, $this, $next, $end);

	$i = 0;
	$j = 0;

	$end = $#lines_tmp;

	until ($i > $end) {
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

# The 'time_calc' subroutine makes sure the current 'time line' is at
# least 1 centisecond greater than previous 'time line'. It also makes
# sure each line has a length of at least 1 centisecond.
sub time_calc {
	my $start_time = shift;
	my $stop_time = shift;

	my($i, $previous);

# If the previous 'time line' is greater than the current one, make the
# current 'time line' 1 centisecond greater than that.
	if ($n > 1) {
		$i = $n - 1;

		$previous = $lines{$i}{stop};

		if ($previous > $start_time) {
			$start_time = $previous + 100;
		}
	}

# If the stop time of the current 'time line' is less than the start
# time, then set it to the start time plus 1 centisecond.
	if ($stop_time < $start_time) {
		$stop_time = $start_time + 100;
	}

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

		push(@lines_tmp, $n, $time_line);

		foreach my $line (@{$lines{$n}{text}}) {
			push(@lines_tmp, $line);
		}

		push(@lines_tmp, '');
	}
}

print "\n";

while (my $fn = shift(@files)) {
	my $of = $fn;
	$of =~ s/$regex{fn}/$1/;
	$of = $of . '-' . int(rand(10000)) . '-' . int(rand(10000)) . '.srt';

	process_sub($fn);

	open(my $srt, '> :raw', $of) or die "Can't open file '$of': $!";
	foreach my $line (@lines_tmp) {
		print $srt $line . "\r\n";
	}
	close($srt) or die "Can't close file '$of': $!";

	say 'Wrote file: ' . $of . "\n";
}
