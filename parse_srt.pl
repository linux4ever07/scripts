#!/usr/bin/perl

# This script simply parses an SRT subtitle file, and prints the content
# without the timestamps.

use 5.34.0;
use strict;
use warnings;
use File::Basename qw(basename);
use Cwd qw(abs_path);
use Encode qw(encode decode find_encoding);

my $script = basename($0);

my(@format);
my($fn, $ext);

if (scalar(@ARGV) == 0) { usage(); }

if (length($ARGV[0])) {
	$fn = abs_path($ARGV[0]);
	$ext = lc(substr($fn, -4));
}

if (! -f $fn or $ext ne '.srt') { usage(); }

$format[0] = qr/^[0-9]+$/;
$format[1] = qr/[0-9]{2}:[0-9]{2}:[0-9]{2},[0-9]{3}/;
$format[2] = qr/^$format[1] --> $format[1]$/;

# The 'usage' subroutine prints syntax, and then quits.
sub usage {
	say 'Usage: ' . $script . ' [srt]' . "\n";
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

# The 'parse_srt' subroutine reads the SRT subtitle file passed to it,
# and prints it without the timestamps.
sub parse_srt {
	my $fn = shift;
	my $i = 0;
	my $j = 0;
	my $n = 0;
	my $switch = 0;
	my($this, $next, $end);
	my(@lines);

	push(@lines, read_decode_fn($fn));

	say $fn . "\n";

	$end = $#lines - 1;

	until ($i >= $end) {
		$j = $i + 1;

		$this = $lines[$i];
		$next = $lines[$j];

		if (length($this) and $this =~ /$format[0]/) {
			if (length($next) and $next =~ /$format[2]/) {
				my(@tmp);

				$i = $i + 2;
				$j = $i + 1;

				$this = $lines[$i];
				$next = $lines[$j];

				if (length($this)) {
					push(@tmp, $this);
				}

				until ($i >= $end) {
					$i = $i + 1;
					$j = $i + 1;

					$this = $lines[$i];
					$next = $lines[$j];

					if (length($this) and $this =~ /$format[0]/) {
						if (length($next) and $next =~ /$format[2]/) {
							$switch = 1;
							last;
						}
					}

					if (length($this)) {
						push(@tmp, $this);
					}
				}

				if (scalar(@tmp) > 0) {
					$n = $n + 1;

					say "";

					foreach my $line (@tmp) {
						say $n . ': ' . $line;
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
