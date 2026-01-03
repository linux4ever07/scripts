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
	my $fn_in = shift;

	my $date = (stat($fn_in))[9];

	my($hash);

	open(my $mf, '< :raw', $fn_in) or die "Can't open '$fn_in': $!";
	$hash = Digest::MD5->new->addfile($mf)->hexdigest;
	close($mf) or die "Can't close '$fn_in': $!";

	$md5h{$hash}{$fn_in} = $date;
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
	my $fn_in = shift;
	my $dn_in = shift;
	my $bn_in = shift;
	my $x_res = shift;
	my $y_res = shift;

	my $ratio_in = shift;
	my $ratio_out = $ratio_in;

	$ratio_out =~ tr/:/_/;

	my $res = join('x', $x_res, $y_res);

	my $dn_out = join('/', $dn_in, $ratio_out, $res);

	my($fn_out);

# If resolution is lower than defined in $limit, then create a directory
# called 'low_res' and move the image there.
	if ($x_res < $limit) {
		$dn_out = join('/', $dn_in, 'low_res', $res);
# If the resolution is not among the accepted aspect ratios, then create
# a directory called 'other_res' and move the image there.
	} elsif (! length($accepted_ratios{$ratio_in})) {
		$dn_out = join('/', $dn_in, 'other_res', $res);
	}

	make_path($dn_out);

	$fn_out = join('/', $dn_out, $bn_in);

	unless (-f $fn_out) {
		move($fn_in, $fn_out) or die "Can't move '$fn_in': $!";
	}

	say $bn_in . ': ' . $res . ' (' . $ratio_in . ')';
}

foreach my $dn_in (@dirs) {
	chdir($dn_in) or die "Can't change to '$dn_in': $!";

	my @files_in = (glob("*"));

	my(@files_out);

# Check if the file is an image, and has the right extension.
	foreach my $fn_in (@files_in) {
		if (! -f $fn_in) { next; }

		$fn_in =~ m/$regex{fn}/;

		my $bn_in = $1;
		my $ext_in = $2;

		$fn_in = $dn_in . '/' . $fn_in;

		my($fn_out);

		my($type, $ext_out) = get_type($fn_in);

		if (! length($type)) { next; }

		if ($type ne 'image') { next; }

		$fn_out = $dn_in . '/' . $bn_in . '.' . $ext_out;

		if ($fn_in ne $fn_out and ! -f $fn_out) {
			move($fn_in, $fn_out) or die "Can't move '$fn_in': $!";
			push(@files_out, $fn_out);
		} else { push(@files_out, $fn_in); }
	}

	@files_in = (@files_out);
	@files_out = ();

	foreach my $fn_in (@files_in) {
		md5sum($fn_in);
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
	foreach my $fn_in (sort(keys(%files))) {
		my $bn_in = basename($fn_in);

		my($x_res, $y_res, $ratio);

		($x_res, $y_res) = get_res($fn_in);
		$ratio = get_ratio($x_res, $y_res);

		if (! length($ratio)) { next; }

		mv_res($fn_in, $dn_in, $bn_in, $x_res, $y_res, $ratio);
	}
}
