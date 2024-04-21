#!/usr/bin/perl

# This script removes duplicate files in the directories given as
# arguments. The behavior differs depending on whether the script was
# run with 1 directory or multiple directories as arguments.

# If the script is run with only 1 directory as argument, the files with
# the oldest modification date will be considered to be the originals,
# when other files with the same MD5 hash are found. In this case, the
# basename can be the same or different. It doesn't matter.

# If the script is run with multiple directories as arguments, it will
# consider the 1st directory as the source, and delete files from the
# other directories that have both the same MD5 hash and the same
# basename.

use 5.34.0;
use strict;
use warnings;
use diagnostics;
use Cwd qw(abs_path);
use Digest::MD5 qw(md5_hex);
use File::Basename qw(basename);
use File::Find qw(find);

my(@dirs, %files, @files_in, @files_out);

while (my $arg = shift(@ARGV)) {
	if (-d $arg) {
		push(@dirs, abs_path($arg));
	} else { usage(); }
}

if (scalar(@dirs) == 0) { usage(); }

# The 'usage' subroutine prints syntax, and then quits.
sub usage {
	say "\n" . 'Usage: ' . basename($0) . ' [dirs...]' . "\n";
	exit;
}

# The 'get_files' subroutine gets all files and directories in the
# directory passed to it as argument.
sub get_files {
	my $dn = shift;

	find({ wanted => \&action, no_chdir => 1 }, $dn);

	sub action {
		if (! -f) { return; }

		my $fn = $File::Find::name;
		my $bn = basename($fn);

		push(@{$files{$bn}}, $fn);
	}
}

# The 'md5sum' subroutine gets the MD5 hash of files.
sub md5sum {
	my $fn = shift;

	my($hash);

	open(my $read_fn, '< :raw', $fn) or die "Can't open '$fn': $!";
	$hash = Digest::MD5->new->addfile($read_fn)->hexdigest;
	close($read_fn) or die "Can't close '$fn': $!";

	return($hash);
}

# This loop gets the file names.
for (my $i = 0; $i < scalar(@dirs); $i++) {
	my $dn = $dirs[$i];

	get_files($dn);

	$files_in[$i] = {%files};
	%files = ();
}

# This loop gets the MD5 hash and modification date of the files.
for (my $i = 0; $i < scalar(@dirs); $i++) {
	foreach my $bn (keys(%{$files_in[$i]})) {
		if (! length($files_in[0]{$bn})) { next; }

		foreach my $fn (@{$files_in[$i]{$bn}}) {
			my $hash = md5sum($fn);
			my $date = (stat($fn))[9];

			$files_out[$i]{$hash}{$fn} = $date;
		}
	}
}

@files_in = (@files_out);
@files_out = ();

# This loop is only run if the script was run with more than 1 directory
# as arguments (since it starts @ element 1 of the array).
for (my $i = 1; $i < scalar(@dirs); $i++) {
	foreach my $hash (keys(%{$files_in[$i]})) {
		if (! length($files_in[0]{$hash})) { next; }

		foreach my $fn (sort(keys(%{$files_in[$i]{$hash}}))) {
			say $fn;

			unlink($fn) or die "Can't remove '$fn': $!";
		}
	}
}

# This loop is only run if the script was run with 1 directory as
# argument.
if (scalar(@dirs) == 1) {
	foreach my $hash (keys(%{$files_in[0]})) {
		if (keys(%{$files_in[0]{$hash}}) == 1) { next; }

		my($date_tmp, $fn_tmp);

		foreach my $fn (sort(keys(%{$files_in[0]{$hash}}))) {
			my $date = $files_in[0]{$hash}{$fn};

			if (! length($date_tmp)) {
				$date_tmp = $date;
				$fn_tmp = $fn;
			}

			if ($date < $date_tmp) {
				$date_tmp = $date;
				$fn_tmp = $fn;
			}
		}

		foreach my $fn (sort(keys(%{$files_in[0]{$hash}}))) {
			if ($fn eq $fn_tmp) { next; }

			say $fn;

			unlink($fn) or die "Can't remove '$fn': $!";
		}
	}
}
