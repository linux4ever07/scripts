#!/usr/bin/perl

# This script simply parses an SRT subtitle file, and prints the content
# without the timestamps.

use 5.34.0;
use strict;
use warnings;
use diagnostics;
use File::Basename qw(basename);
use Cwd qw(abs_path);
use Encode qw(encode decode find_encoding);

my(%regex, @lines, @format, $delim, $fn, $ext);

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

$delim = ' --> ';

$format[0] = qr/[0-9]+/;
$format[1] = qr/([0-9]{2}):([0-9]{2}):([0-9]{2}),([0-9]{3})/;
$format[2] = qr/[0-9]{2}:[0-9]{2}:[0-9]{2},[0-9]{3}/;
$format[3] = qr/^($format[2])$delim($format[2])$/;

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

# The 'parse_srt' subroutine reads the SRT subtitle file passed to it,
# and prints it without the timestamps.
sub parse_srt {
	my $fn = shift;

	my($this, $next, $end, $total_n);
	my(%lines, @lines_tmp);

	my $i = 0;
	my $j = 0;
	my $n = 0;

	push(@lines_tmp, read_decode_fn($fn));

	$end = $#lines_tmp;

	until ($i > $end) {
		$j = $i + 1;

		$this = $lines_tmp[$i];
		$next = $lines_tmp[$j];

		if (length($this) and $this =~ m/$format[0]/) {
			if (length($next) and $next =~ m/$format[3]/) {
				$n += 1;

				$i += 2;
				$j = $i + 1;

				$this = $lines_tmp[$i];
				$next = $lines_tmp[$j];
			}
		}

		if (length($this)) {
			push(@{$lines{$n}{text}}, $this);
		}

		$i += 1;
	}

	$total_n = $n;
	$n = 1;

	@lines_tmp = ();

	until ($n > $total_n) {
		foreach my $line (@{$lines{$n}{text}}) {
			push(@lines_tmp, $n . ': ' . $line);
		}

		push(@lines_tmp, '');

		$n = $n + 1;
	}

	return(@lines_tmp);
}

push(@lines, parse_srt($fn));

say $fn . "\n";

foreach my $line (@lines) {
	say $line;
}
