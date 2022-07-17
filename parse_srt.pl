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
	say "Usage: $script [SRT]\n";
	exit;
}

# The 'parse_srt' subroutine reads the SRT subtitle file passed to it,
# and prints it without the timestamps.
sub parse_srt {
	my $fn = shift;
	my $skip = 0;
	my $n = 1;
	my($this, $next);
	my(@format, @lines);

	$format[0] = qr/^[0-9]+$/;
	$format[1] = qr/[0-9]{2}:[0-9]{2}:[0-9]{2},[0-9]{3}/;
	$format[1] = qr/^$format[1] --> $format[1]$/;

	open(my $srt, '<', $fn) or die "Can\'t open 'SRT': $!";
	chomp(@lines = (<$srt>));
	close($srt) or die "Can\'t close 'SRT': $!";

	say $fn . "\n\n";

	for (my $i=0; $i < $#lines; $i++) {
		if ($skip == 1) {
			$skip = 0;
			next;
		}

		my $j = $i + 1;

		$this = $lines[$i];
		$this =~ s/\r//g;
		$next = $lines[$j];
		$next =~ s/\r//g;

		if (length($this)) {
			if ($this =~ /$format[0]/) {
				if (defined($next)) {
					if ($next =~ /$format[1]/) {
						$skip = 1;
						next;
					}
				}
			}
		}

		if (length($this)) {
			say $n . ': ' . $this;
		} else {
			++$n;
			say "";
		}
	}
}

parse_srt($fn);
