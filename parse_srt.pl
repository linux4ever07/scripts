#!/usr/bin/perl

# This script simply parses an SRT subtitle file, and prints the content
# without the timestamps.

use 5.34.0;
use strict;
use warnings;
use File::Basename qw(basename);
use Cwd qw(abs_path);
use Encode qw(encode decode find_encoding);

my(%regex, @lines, @format, $fn, $ext);

$regex{fn} = qr/^(.*)\.([^.]*)$/;
$regex{charset1} = qr/([^; ]+)$/;
$regex{charset2} = qr/^charset=(.*)$/;
$regex{newline} = qr/(\r){0,}(\n){0,}$/;
$regex{blank1} = qr/^[[:blank:]]*(.*)[[:blank:]]*$/;
$regex{blank2} = qr/^[[:blank:]]*$/;
$regex{blank3} = qr/[[:blank:]]+/;

if (! scalar(@ARGV)) { usage(); }

if (length($ARGV[0])) {
	$fn = abs_path($ARGV[0]);
	$fn =~ m/$regex{fn}/;
	$ext = lc($2);
}

if (! -f $fn or $ext ne 'srt') { usage(); }

$format[0] = qr/[0-9]+/;
$format[1] = qr/[0-9]{2}:[0-9]{2}:[0-9]{2},[0-9]{3}/;
$format[2] = qr/^$format[1] --> $format[1]$/;

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
	my $i = 0;
	my $j = 0;
	my $n = 0;
	my $switch = 0;
	my($this, $next, $end);
	my(@lines_tmp);

	push(@lines_tmp, read_decode_fn($fn));

	push(@lines, $fn, '');

	$end = $#lines_tmp;

	until ($i > $end) {
		$j = $i + 1;

		$this = $lines_tmp[$i];
		$next = $lines_tmp[$j];

		if (length($this) and $this =~ m/$format[0]/) {
			if (length($next) and $next =~ m/$format[2]/) {
				my(@tmp);

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

					if (length($this) and $this =~ m/$format[0]/) {
						if (length($next) and $next =~ m/$format[2]/) {
							$switch = 1;
							last;
						}
					}

					if (length($this)) { push(@tmp, $this); }
				}

				if (scalar(@tmp) > 0) {
					$n = $n + 1;

					push(@lines, '');

					foreach my $line (@tmp) {
						push(@lines, $n . ': ' . $line);
					}
				}

				undef(@tmp);
			}
		}

		if ($switch eq 0) { $i = $i + 1; }
		else { $switch = 0; }
	}
}

parse_srt($fn);

foreach my $line (@lines) {
	say $line;
}
