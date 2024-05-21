#!/usr/bin/perl

# This script came as a result of me accidentally mangling foreign SRT
# (SubRip) subtitles with a faulty regex. I didn't take into account
# that some written languages use various empty characters in
# combination with graphical characters. They don't use the normal space
# character, but they use other similar space characters that are
# invisible. By using a regex that converts all continuous whitespace to
# 1 normal space, some of the graphical characters became unrecognized.
# I figured out a way to fix it, by converting character 32 (next to
# graphical characters) to 160, and then testing if the character is
# still unrecognized (65533). This mostly affects Asian languages, and
# some other languages like Greek or Serbian.

# This script automatically fixes subtitles that have been altered as
# described. It's provided as an example, and parts of it might be
# useful for other scripts in the future.

use 5.34.0;
use strict;
use warnings;
use diagnostics;
use File::Basename qw(basename);
use Cwd qw(abs_path);
use Encode qw(encode decode find_encoding);
use POSIX qw(floor);

my(%regex, %lines, %count);
my(@files, @lines_tmp, @format);
my($line_in, $line_out);
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

if (! scalar(@ARGV)) { usage(); }

while (my $arg = shift(@ARGV)) {
	my($fn, $ext);

	if (! length($arg)) { next; }

	if (! -f $arg) { usage(); }

	if ($arg =~ m/$regex{fn}/) {
		$fn = abs_path($arg);
		$ext = lc($2);
	} else { usage(); }

	if ($ext ne 'srt') { usage(); }

	push(@files, $fn);
}

if (! scalar(@files)) { usage(); }

$delim = '-->';

$format[0] = qr/[0-9]+/;
$format[1] = qr/([0-9]{2,}):([0-9]{2}):([0-9]{2}),([0-9]{3})/;
$format[2] = qr/[0-9]{2,}:[0-9]{2}:[0-9]{2},[0-9]{3}/;
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

# The 'test_line' subroutine will test if the current line has any
# unrecognized characters, and it will also count them.
sub test_line {
	my @chars_out = (@_);

	my($char_in, $char_out);
	my(@chars_test_in, @chars_test_out);

	$count{in} = 0;
	$count{out} = 0;

	for (my $i = 0; $i < scalar(@chars_out); $i++) {
		$chars_out[$i] = chr($chars_out[$i]);
	}

	$line_out = '';

	foreach my $char (@chars_out) {
		$line_out = $line_out . $char;
	}

	@chars_test_in = split('', decode('utf8', $line_in));
	@chars_test_out = split('', decode('utf8', $line_out));

	for (my $i = 0; $i < scalar(@chars_test_in); $i++) {
		$char_in = $chars_test_in[$i];
		$char_out = $chars_test_out[$i];

		if (ord($char_in) eq '65533') { $count{in} += 1; }

		if (! length($char_out)) { next; }

		if (ord($char_out) eq '65533') { $count{out} += 1; }
	}

	$line_out = '';

	foreach my $char (@chars_test_out) {
		$line_out = $line_out . $char;
	}

	$line_out = encode('utf8', $line_out);
}

# The 'fix_chars' subroutine will attempt to restore unrecognized
# characters in the current line.
sub fix_chars {
	$line_in = shift;

	my(@chars_in, @chars_out, @changed, $i, $j);

	@chars_in = split('', $line_in);

	foreach my $char (@chars_in) {
		push(@chars_out, ord($char));
	}

	for ($j = 0; $j < scalar(@chars_out); $j++) {
		if ($j == 0) { next; }

		$i = $j - 1;

		if ($chars_out[$j] == 32) {
			push(@changed, $j);
		}
	}

	test_line(@chars_out);
	$count{last} = $count{out};

	if ($count{in} == 0 and $count{out} == 0) {
		$line_out = $line_in;

		return;
	}

	$i = 0;

	until ($i == scalar(@changed)) {
		$j = $changed[$i];

		$chars_out[$j] = 160;

		test_line(@chars_out);

		if ($count{out} >= $count{last}) {
			$chars_out[$j] = 32;

			test_line(@chars_out);
		}

		$count{last} = $count{out};

		$i += 1;
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
			fix_chars($line);

			push(@lines_tmp, $line_out);
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

	rename($of, $fn) or die "Can't rename file '$of': $!";
}
