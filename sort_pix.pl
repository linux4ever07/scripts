#!/usr/bin/perl

# This script checks the file type, MD5 hash, resolution and aspect
# ratio of each image file in the directories given as argumnets, and
# acts accordingly. If it finds an image that has an identical MD5 hash
# to another image, the second image will be deleted. Only the match
# with the oldest modification date will be kept. For each aspect ratio
# defined in the %accepted_ratios hash, the script will create a
# directory and move matching images there. If the horizontal resolution
# is less than 1024, the script will create a directory called 'low_res'
# and move those files there. The remaining images matching neither of
# these conditions are moved to a directory called 'other_res'.

# The script is not recursive, and it only looks for files that are 1
# level deep in the directory hierarchy.

use 5.34.0;
use strict;
use warnings;
use diagnostics;
use File::Basename qw(basename);
use Digest::MD5;
use File::Copy qw(move);
use File::Path qw(make_path);
use Cwd qw(abs_path);

my(@dirs, %md5h, %files, %regex);

my $limit = 1024;
my %accepted_ratios = ('1:1' => 1, '4:3' => 1, '16:9' => 1, '16:10' => 1);

$regex{fn} = qr/^(.*)\.([^.]*)$/;
$regex{file} = qr/^([^\/]+).*$/;
$regex{magick} = qr/^ +Geometry: ([0-9]+x[0-9]+).*$/;

# The 'usage' subroutine prints syntax, and then quits.
sub usage {
	say "\n" . 'Usage: ' . basename($0) . ' [directory] .. [directory N]' . "\n";
	exit;
}

while (my $arg = shift(@ARGV)) {
	if (-d $arg) {
		push(@dirs, abs_path($arg));
	} else { usage(); }
}

if (! scalar(@dirs)) { usage(); }

# The 'get_type' subroutine gets the file type and the proper extension
# for said file type.
sub get_type {
	my $fn = shift;
	chomp(my $type = `file --brief --mime "$fn"`);
	chomp(my $ext = `file --brief --extension "$fn"`);

	$type =~ s/$regex{file}/$1/;

	if (! length($type)) { return; }

	$ext =~ s/$regex{file}/$1/;

	if (! length($ext)) { return; }

	if ($ext eq 'jpeg') { $ext = 'jpg'; }

	return($type, $ext);
}

# The 'md5sum' subroutine gets the MD5 hash, as well as last
# modification date, of the image.
sub md5sum {
	my $if = shift;

	my $date = (stat($if))[9];

	my($hash);

	open(my $mf, '< :raw', $if) or die "Can't open '$if': $!";
	$hash = Digest::MD5->new->addfile($mf)->hexdigest;
	close($mf) or die "Can't close '$if': $!";

	$md5h{$hash}{$if} = $date;
}

# The 'get_res' subroutine gets the resolution of the image, using
# ImageMagick.
sub get_res {
	my $fn = shift;

	my(@lines, $res, $ratio);

	open(my $output, '-|', 'identify', '-quiet', '-verbose', $fn)
	or die "Can't open 'identify': $!";
	chomp(@lines = (<$output>));
	close($output) or die "Can't close 'identify': $!";

	foreach my $line (@lines) {
		if ($line =~ m/$regex{magick}/) {
			$res = $1;
			last;
		}
	}

	if (! length($res)) { return; }

	return(split('x', $res));
}

# The 'get_ratio' subroutine gets the aspect ratio of a resolution, by
# figuring out the 'greatest common factor' of the 2 numbers.
sub get_ratio {
	my $x_res = shift;
	my $y_res = shift;

	my($x_rem, $y_rem, $ratio);

	my $gcf = $y_res;

	if ($y_res > $x_res) {
		$gcf = $x_res;
	}

	$x_rem = $x_res % $gcf;
	$y_rem = $y_res % $gcf;

	while ($x_rem > 0 or $y_rem > 0) {
		$gcf -= 1;

		$x_rem = $x_res % $gcf;
		$y_rem = $y_res % $gcf;
	}

	$ratio = $x_res / $gcf . ':' . $y_res / $gcf;

	return($ratio);
}

# The 'mv_res' subroutine moves the image to the proper directory, named
# after resolution and aspect ratio.
sub mv_res {
	my $if = shift;
	my $if_dn = shift;
	my $if_bn = shift;
	my $x_res = shift;
	my $y_res = shift;
	my $ratio = shift;

	my $of_ratio = $ratio;

	$of_ratio =~ tr/:/_/;

	my $res = join('x', $x_res, $y_res);

	my $of_dn = join('/', $if_dn, $of_ratio, $res);

	my($of);

# If resolution is lower than defined in $limit, then create a directory
# called 'low_res' and move the image there.
	if ($x_res < $limit) {
		$of_dn = join('/', $if_dn, 'low_res', $res);
# If the resolution is not among the accepted aspect ratios, then create
# a directory called 'other_res' and move the image there.
	} elsif (! length($accepted_ratios{$ratio})) {
		$of_dn = join('/', $if_dn, 'other_res', $res);
	}

	make_path($of_dn);

	$of = join('/', $of_dn, $if_bn);

	unless (-f $of) {
		move($if, $of) or die "Can't move '$if': $!";
	}

	say $if_bn . ': ' . $res . ' (' . $ratio . ')';
}

foreach my $if_dn (@dirs) {
	chdir($if_dn) or die "Can't change to '$if_dn': $!";

	my @files_in = (glob("*"));

	my(@files_out);

# Check if the file is an image, and has the right extension.
	foreach my $if (@files_in) {
		if (! -f $if) { next; }

		$if =~ m/$regex{fn}/;

		my $if_bn = $1;
		my $if_ext = $2;

		$if = $if_dn . '/' . $if;

		my($of);

		my($type, $of_ext) = get_type($if);

		if (! length($type)) { next; }

		if ($type ne 'image') { next; }

		$of = $if_dn . '/' . $if_bn . '.' . $of_ext;

		if ($if ne $of and ! -f $of) {
			move($if, $of) or die "Can't move '$if': $!";
			push(@files_out, $of);
		} else { push(@files_out, $if); }
	}

	@files_in = (@files_out);
	@files_out = ();

	foreach my $if (@files_in) {
		md5sum($if);
	}

	@files_in = ();

# See if there's duplicate MD5 hashes among the files, and delete every
# file except the oldest match.
	foreach my $hash (keys(%md5h)) {
		if (keys(%{$md5h{$hash}}) == 1) { next; }

		my($og_fn, $og_date);

		foreach my $fn (keys(%{$md5h{$hash}})) {
			my $date = $md5h{$hash}{$fn};

			if (! length($og_fn) and ! length($og_date)) {
				$og_fn = $fn;
				$og_date = $date;

				next;
			}

			if ($date < $og_date) {
				$og_fn = $fn;
				$og_date = $date;
			}
		}

		foreach my $fn (keys(%{$md5h{$hash}})) {
			if ($fn ne $og_fn) {
				unlink($fn) or die "Can't remove '$fn': $!";
			}
		}
	}

	foreach my $hash (keys(%md5h)) {
		foreach my $fn (keys(%{$md5h{$hash}})) {
			if (! -f $fn) { next; }

			$files{$fn} = $hash;
		}
	}

	%md5h = ();

# Check the resolution and aspect ratio of the images, and move them to
# their proper directories.
	foreach my $if (sort(keys(%files))) {
		my $if_bn = basename($if);

		my($x_res, $y_res, $ratio);

		($x_res, $y_res) = get_res($if);
		$ratio = get_ratio($x_res, $y_res);

		if (! length($ratio)) { next; }

		mv_res($if, $if_dn, $if_bn, $x_res, $y_res, $ratio);
	}
}
