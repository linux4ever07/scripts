#!/usr/bin/perl

# This script copies files to FAT32 volumes, that are larger than the
# filesystem allows, by splitting them up in multiple parts. Those files
# can later be put back together like this:

# cat file.part1 file.part2 file.part3 > file

# The script is able to both copy individual files, and recursively copy
# directories. It will split files that need to be split, and copy other
# files normally. Files in the destination directory that have the same
# name will be overwritten.

use 5.34.0;
use strict;
use warnings;
use diagnostics;
use Cwd qw(abs_path);
use File::Basename qw(basename);
use File::Find qw(find);
use File::Path qw(make_path);
use File::Copy qw(copy);

my($in, $out);

if (scalar(@ARGV) != 2) { usage(); }
if (-f $ARGV[0] or -d $ARGV[0]) { $in = abs_path($ARGV[0]); }
if (-d $ARGV[1]) { $out = abs_path($ARGV[1]); }

if (! length($in) or ! length($out)) { usage(); }

my(%files, $start);

my $size_limit = 2 ** 32;
my $buffer_size = 64 * (2 ** 10);
my $split = $size_limit / $buffer_size;

# The 'usage' subroutine prints syntax, and then quits.
sub usage {
	say "\n" . 'Usage: ' . basename($0) . ' [source]' . ' [destination]' . "\n";
	exit;
}

# The 'get_files' subroutine gets all files and directories in the
# directory passed to it as argument.
sub get_files {
	my $dn = shift;

	find({ wanted => \&action, no_chdir => 1 }, $dn);

	sub action {
		my $fn = $File::Find::name;
		my $dn = $File::Find::dir;
		my(@path_parts);

		@path_parts = (split('/', $fn));
		splice(@path_parts, 0, $start);
		$fn = join('/', @path_parts);

		@path_parts = (split('/', $dn));
		splice(@path_parts, 0, $start);
		$dn = join('/', @path_parts);

		if (! length($dn)) { $dn = '.'; }

		if (-f) { push(@{$files{$dn}}, $fn); }
	}
}

# The 'copy_split' subroutine splits files that are larger than
# $size_limit, and copies files.
sub copy_split {
	my $if = shift;
	my $of = shift;
	my $of_part = $of . '.part';
	my $size = (stat($if))[7];
	my($read_fn, $write_fn, $buffer);
	my $read_write_n = 0;
	my $part_n = 1;

	if ($if eq $of) {
		say "
in: $if
out: $of

Can\'t copy file to itself!
";
		exit;
	}

	if ($size > $size_limit) {
		$of = $of_part . $part_n;
	} else {
		copy($if, $of) or die "Can't copy '$if': $!";
		return;
	}

	open($read_fn, '< :raw', $if) or die "Can't open '$if': $!";
	open($write_fn, '> :raw', $of) or die "Can't open '$of': $!";
	while (read($read_fn, $buffer, $buffer_size)) {
		if ($read_write_n == $split) {
			$read_write_n = 0;
			$part_n++;
			close($write_fn) or die "Can't close '$of': $!";
			$of = $of_part . $part_n;
			open($write_fn, '> :raw', $of) or die "Can't open '$of': $!";
		}
		print $write_fn $buffer or die "Can't write to '$of': $!";
		$read_write_n++
	}
	close($read_fn) or die "Can't close '$if': $!";
	close($write_fn) or die "Can't close '$of': $!";
}

if (-f $in) {
	copy_split($in, $out . '/' . basename($in));
}

if (-d $in) {
	$start = scalar(split('/', $in));
	get_files($in);

	$out = $out . '/' . basename($in);
	make_path($out);

	foreach my $dn (keys(%files)) {
		if ($dn ne '.') {
			make_path($out . '/' . $dn);
		}

		foreach my $fn (@{$files{$dn}}) {
			my $if = $in . '/' . $fn;
			my $of = $out . '/' . $fn;

			copy_split($if, $of);
		}
	}
}
