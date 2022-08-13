#!/usr/bin/perl

# This script simply parses an SRT subtitle file, and prints the content
# without the timestamps.

use 5.34.0;
use strict;
use warnings;
use File::Basename qw(basename);
use Cwd qw(abs_path);

my $script = basename($0);

my($fn, $ext);

if (length($ARGV[0])) {
	$fn = abs_path($ARGV[0]);
	$ext = lc(substr($fn, -4));
}

if (! -f $fn or $ext ne '.srt') { usage(); }

# The 'usage' subroutine prints syntax, and then quits.
sub usage {
	say 'Usage: ' . $script . ' [srt]' . "\n";
	exit;
}

# The 'parse_srt' subroutine reads the SRT subtitle file passed to it,
# and prints it without the timestamps.
sub parse_srt {
	my $fn = shift;
	my $i = 0;
	my $n = 0;
	my $switch = 0;
	my($this, $next, $end, $j);
	my(@format, @lines);

	$format[0] = qr/^[0-9]+$/;
	$format[1] = qr/[0-9]{2}:[0-9]{2}:[0-9]{2},[0-9]{3}/;
	$format[1] = qr/^$format[1] --> $format[1]$/;

	open(my $srt, '<', $fn) or die "Can\'t open 'SRT': $!";
	foreach my $line (<$srt>) {
		$line =~ s/(\r){0,}(\n){0,}$//g;
		push(@lines, $line);
	}
	close($srt) or die "Can\'t close 'SRT': $!";

	say $fn . "\n";

	$end = $#lines - 1;

	until ($i >= $end) {
		$j = $i + 1;

		$this = $lines[$i];
		$next = $lines[$j];

		my(@tmp);

		if (length($this) and $this =~ /$format[0]/) {
			if (length($next) and $next =~ /$format[1]/) {
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
						if (length($next) and $next =~ /$format[1]/) {
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

		if ($switch eq 0) {
			$i = $i + 1;
		} else {
			$switch = 0;
		}
	}
}

parse_srt($fn);
