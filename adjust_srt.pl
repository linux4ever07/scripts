#!/usr/bin/perl

# This script will shift (and adjust) the timestamps in an SRT (SubRip)
# subtitle file, by the amount specified as arguments.

# The script can shift the subtitle in either direction, positive
# (forward) or negative (backward).

# In the case of modifying the beginning of the subtitle, all timestamps
# will simply be shifted forward or backward by the amount specified.

# In the case of modifying the end of the subtitle, it shifts the last
# timestamp by the full amount, and every timestamp between the 1st and
# last by the approriate amount to make them all line up proportionally.

# This script is designed to streamline the syncing / re-syncing of
# subtitles. The first most common problem with subtitle timestamps is
# when the first line isn't synced. The second most common problem is
# when the last line isn't synced. What causes this is different
# releases of a movie have different intros (studio logos etc.). That
# affects the timestamp of the first line, and hence every following
# line. Also, different releases (and different rips) have different
# framerates. That affects the timestamp of the last line.

# To remedy this, shift the beginning of the subtitle so the first line
# is synced, and then adjust the end of the subtitle so the last line
# is synced.

# Examples:

# adjust_srt.pl -first '-00:00:03,000' 'subtitle.srt'
# adjust_srt.pl -last '+00:00:03,000' 'subtitle.srt'
# adjust_srt.pl -first '+00:00:00,500' -last '-00:00:02,500' 'subtitle.srt'

# The charset of input files will be decoded and then encoded to UTF-8
# in the output.

use 5.34.0;
use strict;
use warnings;
use diagnostics;
use File::Basename qw(basename);
use Cwd qw(abs_path);
use Encode qw(encode decode find_encoding);
use POSIX qw(floor);

my(%regex, %lines);
my(@files, @lines_tmp, @format, @mode, @shift);
my($delim, $n, $total_n);

$regex{fn} = qr/^(.*)\.([^.]*)$/;
$regex{charset1} = qr/([^; ]+)$/;
$regex{charset2} = qr/^charset=(.*)$/;
$regex{newline} = qr/(\r){0,}(\n){0,}$/;
$regex{blank1} = qr/^[[:blank:]]*(.*)[[:blank:]]*$/;
$regex{blank2} = qr/^[[:blank:]]*$/;
$regex{blank3} = qr/ +/;
$regex{last2} = qr/([0-9]{1,2})$/;
$regex{zero} = qr/^0+([0-9]+)$/;

$regex{microdvd_code} = qr/^(\{[^{}]+\})(.*)$/;
$regex{microdvd_bold} = qr/^\{ *y *: *b *\}$/i;
$regex{microdvd_italic} = qr/^\{ *y *: *i *\}$/i;
$regex{microdvd_underline} = qr/^\{ *y *: *u *\}$/i;

$delim = '-->';

$format[0] = qr/[0-9]+/;
$format[1] = qr/([0-9]{2,}):([0-9]{2}):([0-9]{2}),([0-9]{3})/;
$format[2] = qr/[0-9]{2,}:[0-9]{2}:[0-9]{2},[0-9]{3}/;
$format[3] = qr/^($format[2]) *$delim *($format[2])$/;
$format[4] = qr/^\{([0-9]+)\}\{([0-9]+)\}(.*)$/;
$format[5] = qr/^([-+])($format[2])$/;

@shift = (0, 0);

if (! scalar(@ARGV)) { usage(); }

while (my $arg = shift(@ARGV)) {
	my($fn, $ext);

	if (! length($arg)) { next; }

	if ($arg eq '-first') {
		$mode[0] = shift(@ARGV);

		if (! length($mode[0])) { usage(); }

		if ($mode[0] =~ m/$format[5]/) {
			$mode[0] = $1;
			$shift[0] = time_convert($2);
		} else { usage(); }

		next;
	}

	if ($arg eq '-last') {
		$mode[1] = shift(@ARGV);

		if (! length($mode[1])) { usage(); }

		if ($mode[1] =~ m/$format[5]/) {
			$mode[1] = $1;
			$shift[1] = time_convert($2);
		} else { usage(); }

		next;
	}

	if (! -f $arg) { usage(); }

	if ($arg =~ m/$regex{fn}/) {
		$fn = abs_path($arg);
		$ext = lc($2);
	} else { usage(); }

	if ($ext ne 'srt') { usage(); }

	push(@files, $fn);
}

if (! scalar(@files)) { usage(); }

if ($shift[0] == 0 and $shift[1] == 0) { usage(); }

# The 'usage' subroutine prints syntax, and then quits.
sub usage {
	say '
Usage: ' . basename($0) . ' [options] [srt...]

	Options:

-first [-+][h{2}:m{2}:s{2},ms{3}]
	Shift all timestamps

-last [-+][h{2}:m{2}:s{2},ms{3}]
	Adjust timestamps between 1st and last
';

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

	my($h, $m, $s, $ms);

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

# The 'parse_srt_bad' subroutine parses a subtitle that has the SRT
# extension, but is not in the correct (SubRip) format. It's the
# MicroDVD Sub format.
sub parse_srt_bad {
	my($i, $this, $line_tmp);
	my(@code);

	$i = 0;

	until ($i == scalar(@lines_tmp)) {
		$this = $lines_tmp[$i];

		if (length($this) and ! $this =~ m/$format[4]/) {
			return(0);
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

			$line_tmp = $3;
			$line_tmp =~ s/$regex{blank1}/$1/;

			while ($line_tmp =~ m/$regex{microdvd_code}/) {
				push(@code, $1);
				$line_tmp = $2;
			}

			while (my $code = shift(@code)) {
				if ($code =~ m/$regex{microdvd_bold}/) {
					$line_tmp = '<b>' . $line_tmp . '</b>';
				}

				if ($code =~ m/$regex{microdvd_italic}/) {
					$line_tmp = '<i>' . $line_tmp . '</i>';
				}

				if ($code =~ m/$regex{microdvd_underline}/) {
					$line_tmp = '<u>' . $line_tmp . '</u>';
				}
			}

			foreach my $line (split('\|', $line_tmp)) {
				$line =~ s/$regex{blank1}/$1/;

				push(@{$lines{$n}{text}}, $line);
			}
		}

		$i += 1;
	}

	$total_n = $n;

	if ($n > 0) { return(1); }
	else { return(0); }
}

# The 'parse_srt_good' subroutine parses a subtitle in the correct SRT
# (SubRip) format.
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

	if ($n > 0) { return(1); }
	else { return(0); }
}

# The 'shift_first' subroutine shifts all timestamps (incl. the 1st)
# forward or backward.
sub shift_first {
	my($start_time, $stop_time);

	$n = 0;

	until ($n == $total_n) {
		$n += 1;

		$start_time = \$lines{$n}{start};
		$stop_time = \$lines{$n}{stop};

		if ($mode[0] eq '+') {
			$$start_time += $shift[0];
			$$stop_time += $shift[0];
		}

		if ($mode[0] eq '-') {
			$$start_time -= $shift[0];
			$$stop_time -= $shift[0];
		}
	}
}

# The 'adjust_last' subroutine adjusts every timestamp between (and
# incl.) the 2nd and last.
sub adjust_last {
	my($start_time, $stop_time, $offset);
	my(@interval_in, @interval_out);

	$n = $total_n;

	if ($n > 1) { $n -= 1; }

	$interval_in[0] = floor($shift[1] / $n);
	$interval_in[1] = floor($shift[1] % $n);

	$n = $total_n;

	while ($n > 1) {
		$interval_out[$n] = $interval_in[0];

		$n -= 1;
	}

	while ($interval_in[1] > 0) {
		if ($n == 1) { $n = $total_n; }

		$interval_in[1] -= 1;
		$interval_out[$n] += 1;

		$n -= 1;
	}

	$n = 0;
	$offset = 0;

	until ($n == $total_n) {
		$n += 1;

		$start_time = \$lines{$n}{start};
		$stop_time = \$lines{$n}{stop};

		if (! length($interval_out[$n])) { next; }

		$offset += $interval_out[$n];

		if ($mode[1] eq '+') {
			$$start_time += $offset;
			$$stop_time += $offset;
		}

		if ($mode[1] eq '-') {
			$$start_time -= $offset;
			$$stop_time -= $offset;
		}
	}
}

# The 'process_sub' subroutine reads a subtitle file, parses and
# processes it.
sub process_sub {
	my $fn = shift;

	$n = 0;
	$total_n = 0;

	@lines_tmp = ();
	%lines = ();

	push(@lines_tmp, read_decode_fn($fn));

	if (! parse_srt_bad()) { parse_srt_good(); }

	if ($shift[0] > 0) { shift_first(); }
	if ($shift[1] > 0) { adjust_last(); }

	@lines_tmp = ();
}

# The 'print_sub' subroutine prints the finished subtitle.
sub print_sub {
	my($start_time, $stop_time, $time_line);

	$n = 0;

	until ($n == $total_n) {
		$n += 1;

		$start_time = time_convert($lines{$n}{start});
		$stop_time = time_convert($lines{$n}{stop});

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
	print_sub();

	open(my $srt, '> :raw', $of) or die "Can't open file '$of': $!";
	foreach my $line (@lines_tmp) {
		print $srt $line . "\r\n";
	}
	close($srt) or die "Can't close file '$of': $!";

	say 'Wrote file: ' . $of . "\n";
}
