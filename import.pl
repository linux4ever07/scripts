#!/usr/bin/perl

# This script is meant to import FLAC albums to a FLAC music library
# directory.

use v5.34;
use strict;
use warnings;
use diagnostics;
use Cwd qw(abs_path);
use File::Basename qw(basename);
use File::Find qw(find);
use File::Path qw(make_path);
use File::Copy qw(copy);
use Encode qw(decode find_encoding);

my @required_tags = qw(artist album tracknumber title);
my @log_accepted = qw(EAC 'Exact Audio Copy' 'XLD X Lossless Decoder' cdparanoia Rubyripper whipper);
my(%regex, %files, %tags_ref, %imported, @dirs, @logs, $library, $tracks);

$regex{charset1} = qr/([^; ]+)$/;
$regex{charset2} = qr/^charset=(.*)$/;

$regex{newline} = qr/(\r){0,}(\n){0,}$/;
$regex{quote} = qr/^(\")|(\")$/;
$regex{space} = qr/(^\s*)|(\s*$)/;
$regex{tag} = qr/^([^=]+)=(.*)$/;
$regex{fraction} = qr/^([0-9]+)\s*\/\s*([0-9]+)$/;
$regex{disc} = qr/\s*[[:punct:]]?(cd|disc)\s*([0-9]+)(\s*of\s*([0-9]+))?[[:punct:]]?\s*$/i;

# Check if the necessary commands are installed to test FLAC files.
my $flac_req = `command -v metaflac`;

if (! length($flac_req)) {
	say "\n" . 'This script needs \'metaflac\' installed!' . "\n";
	exit;
}

while (my $arg = shift(@ARGV)) {
	if (-d $arg) {
		push(@dirs, abs_path($arg));
	} else { usage(); }
}

if (scalar(@dirs) < 2) { usage(); }

$library = shift(@dirs);

# The 'usage' subroutine prints syntax, and then quits.
sub usage {
	say "\n" . 'Usage: ' . basename($0) . ' [FLAC library directory] .. [directory N]' . "\n";
	exit;
}

# The 'get_files' subroutine gets a list of FLAC files in the directory
# passed to it.
sub get_files {
	my $dn = shift;

	my(%tags);

	undef(%files);
	undef(@logs);

	opendir(my $dh, $dn) or die "Can't open directory '$dn': $!";
	foreach my $bn (readdir($dh)) {
		my $fn = $dn . '/' . $bn;

		if (! -f $fn) { next; }

		if ($bn =~ m/\.flac$/i) { $tags{$fn} = { gettags($fn) }; }
		if ($bn =~ m/\.log$/i) { check_log($fn); }
	}
	closedir $dh or die "Can't close directory '$dn': $!";

	foreach my $fn (keys(%tags)) {
		my $tags_ref = \$tags{$fn};

		existstag($fn, $tags_ref, @required_tags);

		foreach my $field (keys(%{$$tags_ref})) {
			$files{$fn}{$field} = $$tags_ref->{$field}[0];
		}
	}

	$tracks = keys(%files);
}

# The 'gettags' subroutine reads the tags from a FLAC file.
sub gettags {
	my $fn = shift;

	my(%alltags, @lines);

	open(my $output, '-|', 'metaflac', '--no-utf8-convert', '--export-tags-to=-', $fn)
	or die "Can't open metaflac: $!";
	chomp(@lines = (<$output>));
	close($output) or die "Can't close metaflac: $!";

	while (my $line = shift(@lines)) {
		my($field, $value);

		$line =~ s/$regex{quote}//g;

		if ($line =~ m/$regex{tag}/) {
			$field = lc($1);
			$value = $2;

			$field =~ s/$regex{space}//g;
			$value =~ s/$regex{space}//g;
			$value =~ tr/a-zA-Z0-9\.\-_ //dc;
			$value =~ s/\s+/ /g;

			if ($field eq 'album' or $field eq 'albumartist') {
				$value =~ s/^\.+//g;
			}
		}

		if (! length($field) or ! length($value)) { next; }

		push(@{$alltags{$field}}, $value);
	}

	return(%alltags);
}

# The 'existstag' subroutine checks for the existence of required tags.
# If it doesn't find them, it quits.
sub existstag {
	my $fn = shift;
	my $tags_ref = shift;

	my(@missing_tags);

	while (my $field = shift(@_)) {
		if (length($$tags_ref->{$field}[0])) { next; }

		push(@missing_tags, $field);
	}

	if (! scalar(@missing_tags)) { return; }

	foreach my $field (@missing_tags) {
		say $fn . ': missing ' . $field . ' tag';
	}

	exit;
}

# The 'check_log' subroutine checks the log file to see if it contains
# any of the words in @log_accepted. Most of the code here is to deal
# with correctly decoding the character encoding in the log file. We do
# this to be able to properly match the words.
sub check_log {
	my $fn = shift;

	my($file_enc, $tmp_enc, $enc, $line1);

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
	$line1 = <$text>;
	if (length($enc)) { $line1 = decode($enc, $line1); }
	$line1 =~ s/$regex{newline}//g;
	close $text or die "Can't close file '$fn': $!";

	foreach my $req (@log_accepted) {
		if (! $line1 =~ m/$req/) { next; }

		push(@logs, $fn);
		last;
	}
}

# The 'mk_refs' subroutine creates references for other subroutines to
# have easier access to tags.
sub mk_refs {
	my $fn = shift;

	$tags_ref{discnumber} = \$files{$fn}{discnumber};
	$tags_ref{totaldiscs} = \$files{$fn}{totaldiscs};
	$tags_ref{disctotal} = \$files{$fn}{disctotal};
	$tags_ref{tracknumber} = \$files{$fn}{tracknumber};
	$tags_ref{totaltracks} = \$files{$fn}{totaltracks};
	$tags_ref{tracktotal} = \$files{$fn}{tracktotal};
	$tags_ref{artist} = \$files{$fn}{artist};
	$tags_ref{albumartist} = \$files{$fn}{albumartist};
	$tags_ref{album} = \$files{$fn}{album};
	$tags_ref{title} = \$files{$fn}{title};
}

# The 'discnumber' subroutine creates the DISCNUMBER tag, if it doesn't
# exist already. DISCTOTAL is also added, if possible. This subroutine
# needs to be run before 'albumartist', and 'totaltracks'.
sub discnumber {
	my $fn = shift;
	my $dn = shift;

	if (length(${$tags_ref{discnumber}})) {
		if (${$tags_ref{discnumber}} =~ m/$regex{fraction}/) {
			${$tags_ref{discnumber}} = $1;

			if (! length(${$tags_ref{totaldiscs}})) {
				${$tags_ref{totaldiscs}} = $2;
			}
		}
	}

	if (! length(${$tags_ref{discnumber}})) {
		if (${$tags_ref{album}} =~ m/$regex{disc}/) {
			${$tags_ref{discnumber}} = $2;

			if (! length(${$tags_ref{totaldiscs}}) and length($4)) {
				${$tags_ref{totaldiscs}} = $4;
			}

			${$tags_ref{album}} =~ s/$regex{disc}//;
		}
	}

	if (! length(${$tags_ref{discnumber}})) {
		if ($dn =~ m/$regex{disc}/) {
			${$tags_ref{discnumber}} = $2;

			if (! length(${$tags_ref{totaldiscs}}) and length($4)) {
				${$tags_ref{totaldiscs}} = $4;
			}
		} else { ${$tags_ref{discnumber}} = 1; }
	}

	if (! length(${$tags_ref{totaldiscs}})) {
		if (length(${$tags_ref{disctotal}})) {
			${$tags_ref{totaldiscs}} = ${$tags_ref{disctotal}};
		}
	}
}

# The 'albumartist' subroutine creates the ALBUMARTIST tag, if it
# doesn't exist already.
sub albumartist {
	my $fn = shift;

	if (! length(${$tags_ref{albumartist}})) {
		my(%artist, $max);

		if ($tracks == 1) { $max = $tracks; }
		else { $max = $tracks / 2; }

		foreach my $fn (keys(%files)) {
			$tags_ref{tmp} = \$files{$fn}{artist};

			$artist{${$tags_ref{tmp}}} = 1;
		}

		if (keys(%artist) > $max) {
			${$tags_ref{albumartist}} = 'Various Artists';
		} else { ${$tags_ref{albumartist}} = ${$tags_ref{artist}}; }
	}
}

# The 'import' subroutine imports a FLAC album to the FLAC library.
sub import {
	my $if_dn = shift;

	my $flac_n = 0;
	my $log_n = 0;

	my($of_dn, $imported_ref);

	foreach my $if (sort(keys(%files))) {
		my($of_bn, $of);

		mk_refs($if);
		discnumber($if, $if_dn);
		albumartist($if);

		$imported_ref = \$imported{${$tags_ref{albumartist}}}{${$tags_ref{album}}};

		$of_dn = $library . '/' . ${$tags_ref{albumartist}} . '/' . ${$tags_ref{album}};

		$of_bn = sprintf('%d-%02d. %s.flac', ${$tags_ref{discnumber}}, ${$tags_ref{tracknumber}}, ${$tags_ref{title}});

		$of = $of_dn . '/' . $of_bn;

		if (length($$imported_ref->{${$tags_ref{discnumber}}})) {
			say $of_dn . ': already exists';
			say 'Skipping...' . "\n";
			return;
		}

		if (-f $of) {
			say $of . ': already exists';
			say 'Skipping...' . "\n";
			return;
		}

		make_path($of_dn);

		say 'Copying \'' . $if . '\'' . "\n\t" . 'to \'' . $of . '\'...';
		copy($if, $of) or die "Copy failed: $!";
		$flac_n++;
	}

	say 'Copied ' . $flac_n . ' / ' . $tracks . ' files from \'' . ${$tags_ref{album}} . '\'.' . "\n";

	foreach my $if (@logs) {
		my($of_bn, $of);

		$of_bn = ${$tags_ref{discnumber}} . '-' . ${$tags_ref{album}} . '.log';

		$of = $of_dn . '/' . $of_bn;

		if (-f $of) {
			say $of . ': already exists';
			say 'Skipping...' . "\n";
			return;
		}

		say 'Copying \'' . $if . '\'' . "\n\t" . 'to \'' . $of . '\'...' . "\n";
		copy($if, $of) or die "Copy failed: $!";
		$log_n++;
	}

# Saves ALBUMARTIST, ALBUM and DISCNUMBER tags, to remember what albums
# have been copied over. This is to allow multi-disc albums to be
# imported, as long as it's done in the same session of the script.
# The reason it works is because different disc directories of an album
# usually have the DISCNUMBER tag set.
	$$imported_ref->{${$tags_ref{discnumber}}} = 1;
}

while (my $dn = shift(@dirs)) {
	find({ wanted => \&action, no_chdir => 1 }, $dn);

	sub action {
		if (! -d) { return; }

		my $dn = $File::Find::name;
		get_files($dn);

		if ($tracks > 0) {
			say $dn . ': importing...' . "\n";
			import($dn);
		} else { say $dn . ': contains no FLAC files'; }
	}
}
