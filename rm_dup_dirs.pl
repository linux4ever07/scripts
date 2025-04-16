#!/usr/bin/perl

# This script recursively removes duplicate sub-directories in the
# directories given as arguments. It starts at maximum depth and works
# its way backwards to the root of the directories.

# This can be useful if there are multiple different versions of the
# same directory tree, but with slight modifications. The script will
# remove all the sub-directories that are identical, making it easier to
# merge the directory trees if needed.

use 5.34.0;
use strict;
use warnings;
use diagnostics;
use Cwd qw(abs_path);
use Digest::MD5 qw(md5_hex);
use File::Basename qw(basename);
use File::Find qw(find);

my(@dirs, %dirs, @depths, %files, @files_in, @files_out);

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

# The 'md5sum' subroutine gets the MD5 hash of files.
sub md5sum {
	my $fn = shift;

	my($hash);

	open(my $read_fn, '< :raw', $fn) or die "Can't open '$fn': $!";
	$hash = Digest::MD5->new->addfile($read_fn)->hexdigest;
	close($read_fn) or die "Can't close '$fn': $!";

	return($hash);
}

# The 'get_dirs' subroutine gets all directories in the directory
# passed to it as argument.
sub get_dirs {
	my $dn = shift;

	find({ wanted => \&action, no_chdir => 1 }, $dn);

	sub action {
		if (! -d) { return; }

		my $fn = $File::Find::name;
		my $bn = basename($fn);

		my @path_parts = split('/', $fn);
		my $depth = scalar(@path_parts);

		$dirs{$depth}{$fn} = $bn;
	}
}

# The 'get_files' subroutine gets all files in the directory passed to
# it as argument.
sub get_files {
	my $dn = shift;

	my(@files, $fn, $hash);

	opendir(my $dh, $dn) or die "Can't open '$dn': $!";
	@files = readdir($dh);
	closedir($dh) or die "Can't close '$dn': $!";

	foreach my $bn (@files) {
		$fn = "$dn/$bn";

		if (! -f $fn) { next; }

		$hash = md5sum($fn);

		$files{$dn}{$fn}{$bn} = $hash;
	}
}

# Gets the depths and directories.
foreach my $dn (@dirs) {
	get_dirs($dn);
}

# Sorts the depths in descending order.
@depths = sort { $b <=> $a } keys(%dirs);

# Gets the list of files contained in each directory.
foreach my $depth (@depths) {
	foreach my $dn (keys(%{$dirs{$depth}})) {
		get_files($dn);
	}
}

# This loop goes through all the directories, and compares the number of
# files, as well as MD5 hashes. If multiple different directories have
# the same number of files (with the same names), as well as identical
# MD5 hashes, then remove the duplicate files. This is not recursive, so
# there's no risk of accidentally removing non-empty sub-directories.
foreach my $depth_in (@depths) {
	foreach my $dn_in (sort(keys(%{$dirs{$depth_in}}))) {
		my $dn_bn_in = $dirs{$depth_in}{$dn_in};

		@files_in = sort(keys(%{$files{$dn_in}}));
		if (scalar(@files_in) == 0) { next; }

		foreach my $depth_out (@depths) {
			foreach my $dn_out (sort(keys(%{$dirs{$depth_out}}))) {
				if ($dn_in eq $dn_out) { next; }

				my $dn_bn_out = $dirs{$depth_out}{$dn_out};

				if ($dn_bn_in ne $dn_bn_out) { next; }

				@files_out = sort(keys(%{$files{$dn_out}}));
				if (scalar(@files_out) == 0) { next; }

				if (scalar(@files_in) != scalar(@files_out)) { next; }

				my $switch = 0;

				for (my $i = 0; $i < scalar(@files_in); $i++) {
					my $fn_in = $files_in[$i];
					my $fn_out = $files_out[$i];

					my @fn_bn_in = keys(%{$files{$dn_in}{$fn_in}});
					my @fn_bn_out = keys(%{$files{$dn_out}{$fn_out}});

					if ($fn_bn_in[0] ne $fn_bn_out[0]) {
						$switch = 1;

						last;
					}

					my $hash_in = $files{$dn_in}{$fn_in}{$fn_bn_in[0]};
					my $hash_out = $files{$dn_out}{$fn_out}{$fn_bn_out[0]};

					if ($hash_in ne $hash_out) {
						$switch = 1;

						last;
					}
				}

				if ($switch == 1) { next; }

				foreach my $fn_in (@files_out) {
					say 'Deleting: ' . $fn_in;

					unlink($fn_in) or die "Can't remove '$fn_in': $!";
				}

				$files{$dn_out} = ();
			}
		}
	}
}

# Removes empty directories. Try to remove directories that are probably
# empty. If they're not empty, no harm done, as the 'rmdir' command can
# only remove directories that are actually empty.
foreach my $depth_in (@depths) {
	foreach my $dn_in (sort(keys(%{$dirs{$depth_in}}))) {
		@files_in = sort(keys(%{$files{$dn_in}}));

		if (scalar(@files_in) == 0) {
			say 'Deleting: ' . $dn_in;

			rmdir($dn_in);
		}
	}
}
