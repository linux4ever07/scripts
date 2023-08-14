#!/usr/bin/perl

# This script merges an arbitrary number of SRT subtitle files to 1
# file, and adjusts the timestamps. This is useful when a movie that's
# split accross multiple discs has been merged to 1 file, and the
# subtitles also need to be merged. Or just merging SRT subtitle files
# in general.

# The script can also be useful in the case when a subtitle only has
# the English parts, but other subtitles have the foreign dialogue
# parts. If that's the case, manually delete all the lines that exist
# in both subtitles, and then merge them using this script.

# The output file might still need to be edited in a subtitle editor to
# be properly synced to the movie file, but at least most of the work
# will already be done.

# The script has 2 modes, 'linear' and 'mix'. In linear mode, it just
# appends each subtitle file and shifts the timestamps. In mix mode, it
# will sort and number the lines based on the start timestamps.

# The charset of input files will be decoded and then encoded to UTF-8
# in the output.

use 5.34.0;
use strict;
use warnings;
use diagnostics;
use File::Basename qw(basename);
use Cwd qw(abs_path cwd);
use Encode qw(encode decode find_encoding);
use POSIX qw(floor);

my(%regex, %lines, %start_time, %stop_time);
my(@files, @lines_tmp, @format);
my($mode, $dn, $of, $delim, $offset);

$regex{fn} = qr/^(.*)\.([^.]*)$/;
$regex{charset1} = qr/([^; ]+)$/;
$regex{charset2} = qr/^charset=(.*)$/;
$regex{newline} = qr/(\r){0,}(\n){0,}$/;
$regex{blank1} = qr/^[[:blank:]]*(.*)[[:blank:]]*$/;
$regex{blank2} = qr/^[[:blank:]]*$/;
$regex{blank3} = qr/ +/;
$regex{zero} = qr/^0+([0-9]+)$/;

$offset = 0;

$dn = cwd();
$of = $dn . '/' . 'merged_srt' . '-' . int(rand(10000)) . '-' . int(rand(10000)) . '.srt';

if (! scalar(@ARGV)) { usage(); }

while (my $arg = shift(@ARGV)) {
	my($fn, $ext);

	if (! length($arg)) { next; }

	if ($arg eq '-linear') {
		$mode = 'linear';

		next;
	}

	if ($arg eq '-mix') {
		$mode = 'mix';

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

if (! length($mode)) { usage(); }

$delim = '-->';

$format[0] = qr/[0-9]+/;
$format[1] = qr/([0-9]{2}):([0-9]{2}):([0-9]{2}),([0-9]{3})/;
$format[2] = qr/[0-9]{2}:[0-9]{2}:[0-9]{2},[0-9]{3}/;
$format[3] = qr/^($format[2]) *$delim *($format[2])$/;
$format[4] = qr/^\{([0-9]+)\}\{([0-9]+)\}(.*)$/;

# The 'usage' subroutine prints syntax, and then quits.
sub usage {
	say "\n" . 'Usage: ' . basename($0) . ' [-linear|-mix] [srt...]' . "\n";
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

# The 'parse_srt_bad' subroutine parses a subtitle that has the SRT
# extension, but is not in the correct (SubRip) format. It's another
# semi-common format.
sub parse_srt_bad {
	my($i, $n, $this);
	my(%tmp);

	%start_time = ();
	%stop_time = ();

	$i = 0;

	$n = 0;

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

			$start_time{in} = frames2ms($1);
			$stop_time{in} = frames2ms($2);

			if ($mode eq 'linear') {
				$start_time{in} += $offset;
				$stop_time{in} += $offset;
			}

			$tmp{stop} = $stop_time{in};
			$tmp{text} = ();

			push(@{$tmp{text}}, split('\|', $3));

			push(@{$lines{$start_time{in}}}, {%tmp});
		}

		$i += 1;
	}

	if (length($stop_time{in})) { $offset += $stop_time{in}; }

	if ($n > 0) { return(1); }
	else { return(0); }
}

# The 'parse_srt_good' subroutine parses a subtitle in the correct SRT
# (SubRip) format.
sub parse_srt_good {
	my($i, $j, $n, $this, $next);
	my(%tmp);

	%start_time = ();
	%stop_time = ();

	$i = 0;
	$j = 0;

	$n = 0;

	until ($i == scalar(@lines_tmp)) {
		$j = $i + 1;

		$this = $lines_tmp[$i];
		$next = $lines_tmp[$j];

		if (length($this) and $this =~ m/$format[0]/) {
			if (length($next) and $next =~ m/$format[3]/) {
				$n += 1;

				if ($n > 1) { push(@{$lines{$start_time{in}}}, {%tmp}); }

				$start_time{in} = time_convert($1);
				$stop_time{in} = time_convert($2);

				if ($mode eq 'linear') {
					$start_time{in} += $offset;
					$stop_time{in} += $offset;
				}

				$tmp{stop} = $stop_time{in};
				$tmp{text} = ();

				$i += 2;

				$this = $lines_tmp[$i];
			}
		}

		if (length($this)) {
			push(@{$tmp{text}}, $this);
		}

		$i += 1;
	}

	if (length($start_time{in})) { push(@{$lines{$start_time{in}}}, {%tmp}); }

	if (length($stop_time{in})) { $offset += $stop_time{in}; }

	if ($n > 0) { return(1); }
	else { return(0); }
}

# The 'process_sub' subroutine reads a subtitle file, parses and
# processes it.
sub process_sub {
	my $fn = shift;

	@lines_tmp = ();

	push(@lines_tmp, read_decode_fn($fn));

	if (! parse_srt_bad()) {
		parse_srt_good();
	}

	@lines_tmp = ();
}

# The 'print_sub' subroutine prints the finished subtitle.
sub print_sub {
	my($time_line, $end, $n);
	my(%tmp);

	%start_time = ();
	%stop_time = ();

	$n = 0;

	foreach my $start_time (sort { $a <=> $b } keys(%lines)) {
		$start_time{in} = $start_time;

		$end = scalar(@{$lines{$start_time{in}}});

		for (my $i = 0; $i < $end; $i++) {
			$n += 1;

			%tmp = (%{$lines{$start_time{in}}[$i]});

			$stop_time{in} = $tmp{stop};

			$start_time{out} = $stop_time{in};
			$stop_time{out} = $stop_time{in};

			$start_time{out} = time_convert($start_time{out});
			$stop_time{out} = time_convert($stop_time{out});

			$time_line = $start_time{out} . ' ' . $delim . ' ' . $stop_time{out};

			push(@lines_tmp, $n, $time_line);

			foreach my $line (@{$tmp{text}}) {
				$line =~ s/$regex{blank1}/$1/;

				push(@lines_tmp, $line);
			}

			push(@lines_tmp, '');
		}
	}
}

while (my $fn = shift(@files)) {
	process_sub($fn);
}

print_sub();

open(my $srt, '> :raw', $of) or die "Can't open file '$of': $!";
foreach my $line (@lines_tmp) {
	print $srt $line . "\r\n";
}
close($srt) or die "Can't close file '$of': $!";

say "\n" . 'Wrote file: ' . $of . "\n";
