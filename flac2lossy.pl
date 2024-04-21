#!/usr/bin/perl

# This script is a multithreaded audio batch encoder. It encodes FLAC
# albums to lossy codecs / formats.

# Currently supported codecs are:

# * MP3 (lame)
# * AAC (ffmpeg)
# * Ogg Vorbis (oggenc)
# * Opus (opusenc)

# The script assumes the input is Stereo, 44.1 kHz. At least in the case
# of AAC, as ffmpeg needs to know the nature of the input when using
# pipes.

# The FLAC files are decoded, and stored in RAM up to the limit defined
# in $disk_size. The $file_stack variable is used to count the total
# amount of data decoded and stored in RAM at any time.

# The output files are stored here:
# ${HOME}/${ext}/${albumartist}/${album}/

# The script looks for the CPU core count in /proc/cpuinfo, and starts
# as many threads as it finds cores. The threads are left waiting for
# files to be enqueued. If a single FLAC file is greater than or equal
# to 1 GB, then the script will get stuck. However, that's unlikely to
# happen, but if for some reason you need to encode larger files, just
# raise the limit in $disk_size.

# I've done my best to choose sane default settings for the various
# codecs, generating high quality while maintaining a low file size.
# I've attempted to make the settings somewhat compliant with scene
# rules (with bitrates around 192 kbps).

# Modern codecs don't need as many bits as MP3 does to sound good.
# That's why Opus uses only 160 kbps, cause it's a newer codec than the
# others. MP3 is the oldest one out of the bunch, hence the least
# effective.

# The reason for not choosing insanely high bitrates, like 320 kbps (in
# the case of MP3), is that the whole point of transcoding lossless to
# lossy is to save space. It's mostly done to put music on portable
# audio players, such as phones or iPods (and other devices that have
# limited memory).

# It's not possible to choose bitrate or quality when running the
# script. It's only possible to choose audio format. This is to keep
# things simple.

use 5.34.0;
use strict;
use warnings;
use diagnostics;
use Cwd qw(abs_path);
use File::Path qw(make_path);
use File::Basename qw(basename);

use threads qw(yield);
use threads::shared;
use Thread::Queue;

my %pcm :shared;

my $file_stack :shared = 0;
my $disk_size = 1000000000;

my $files_q = Thread::Queue->new();

my(%regex, %files, @dirs, @opts, @threads, $mode);

$regex{newline} = qr/(\r){0,}(\n){0,}$/;
$regex{date} = qr/^([0-9]{4})/;
$regex{quote} = qr/^(\")|(\")$/;
$regex{space} = qr/(^\s*)|(\s*$)/;
$regex{tag} = qr/^([^=]+)=(.*)$/;

my @required_tags = qw(albumartist album date discnumber tracknumber title);

# Get the number of available CPU cores. Add 1 to this number, which
# will lead to an extra thread being created, maximizing performance.
chomp(my $cores = `grep -c '^processor' '/proc/cpuinfo'`);
$cores++;

# The 'usage' subroutine prints usage instructions, and then quits.
sub usage {
	say '
Usage: ' . basename($0) . ' [format] [FLAC directory 1] .. [FLAC directory N]

	Formats:
-mp3
	Encode to the MP3 audio format (using lame)
-aac
	Encode to the AAC audio format (using ffmpeg)
-ogg
	Encode to the Ogg Vorbis audio format (using oggenc)
-opus
	Encode to the Opus audio format (using opusenc)
';

	exit;
}

# Choose script mode (codec) based on arguments given to the script.
my $arg = shift(@ARGV);

if ($arg eq '-mp3') {
	$mode = 'mp3';

	@opts = ('lame', '--silent', '-q', '0', '-V', '2', '--id3v2-only');
}

if ($arg eq '-aac') {
	$mode = 'aac';

	@opts = ('ffmpeg', '-loglevel', 'fatal', '-f', 's16le', '-ar', '44.1k', '-ac', '2', '-i', 'pipe:', '-strict', '-2', '-c:a', 'aac', '-b:a', '192k', '-profile:a', 'aac_ltp');
}

if ($arg eq '-ogg') {
	$mode = 'ogg';

	@opts = ('oggenc', '--quiet', '--quality=6');
}

if ($arg eq '-opus') {
	$mode = 'opus';

	@opts = ('opusenc', '--quiet', '--bitrate', '160', '--vbr', '--music', '--comp', '10');
}

if (! scalar($mode)) {
	usage();
}

# If the remaining arguments are directories, store them in the @dirs
# array.
while (my $arg = shift(@ARGV)) {
	if (-d $arg) {
		my $dn = abs_path($arg);
		get_dirs($dn);
	} else { usage(); }
}

# Print usage instructions if @dirs array is empty.
if (! scalar(@dirs)) { usage(); }

foreach my $dn (@dirs) { get_files($dn); }

check_cmd('flac', 'metaflac', 'lame', 'ffmpeg', 'oggenc', 'opusenc');

# The 'check_cmd' subroutine checks if the necessary commands are
# installed. If any of the commands are missing, print them and quit.
sub check_cmd {
	my(@missing_pkg, $stdout);

	while (my $cmd = shift(@_)) {
		`command -v "$cmd" 1>&-`;

		if ($? != 0) {
			push(@missing_pkg, $cmd);
		}
	}

	if (scalar(@missing_pkg) > 0) {
		say "\n" . 'You need to install the following through your package manager:' . "\n";
		print(join("\n", @missing_pkg));
		say "\n";

		exit;
	}
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

# The 'get_dirs' subroutine finds all the sub-directories under the FLAC
# directories given as arguments to the script.
sub get_dirs {
	my $dn = shift;

	my(@lines);

	open(my $find, '-|', 'find', $dn, '-type', 'd', '-nowarn')
	or die "Can't run 'find': $!";
	chomp(@lines = (<$find>));
	close($find) or die "Can't close 'find': $!";

	push(@dirs, @lines);
}

# The 'get_files' subroutine gets a list of FLAC files in the directory
# passed to it.
sub get_files {
	my $dn = shift;

	my(%tags);

	opendir(my $dh, $dn) or die "Can't open directory '$dn': $!";
	foreach my $bn (readdir($dh)) {
		my $fn = $dn . '/'. $bn;

		if (! -f $fn) { next; }

		if ($bn =~ m/\.flac$/i) { $tags{$fn} = { gettags($fn) }; }
	}
	closedir $dh or die "Can't close directory '$dn': $!";

	foreach my $fn (keys(%tags)) {
		my $tags_ref = \$tags{$fn};

		existstag($fn, $tags_ref, @required_tags);

		$pcm{$fn} = 1;

		foreach my $field (keys(%{$$tags_ref})) {
			$files{$fn}{$field} = $$tags_ref->{$field}[0];
		}
	}
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

# The 'mk_refs' subroutine creates references for other subroutines to
# have easier access to tags.
sub mk_refs {
	my $fn = shift;
	my $tags_ref = shift;

	$$tags_ref{date} = \$files{$fn}{discnumber};
	$$tags_ref{discnumber} = \$files{$fn}{discnumber};
	$$tags_ref{tracknumber} = \$files{$fn}{tracknumber};
	$$tags_ref{artist} = \$files{$fn}{artist};
	$$tags_ref{albumartist} = \$files{$fn}{albumartist};
	$$tags_ref{album} = \$files{$fn}{album};
	$$tags_ref{title} = \$files{$fn}{title};
}

# The 'files2queue' subroutine puts files in the queue, and loads them
# into RAM.
sub files2queue {
	my($size, $free);

	foreach my $fn (sort(keys(%files))) {
		$size = (stat($fn))[7];

		$free = $disk_size - $file_stack;

# If file size is bigger than the amount of free RAM, wait.
		while ($size > $free) {
			yield();
			$free = $disk_size - $file_stack;
		}

		$size = decode($fn);

		$files_q->enqueue($fn, $size);
	}

	$files_q->end();
}

# The 'name' subroutine generates file names for output files.
sub name {
	my $fn = shift;
	my $ext = shift;
	my $tags_ref = shift;

	my(@tags, $of, $of_bn, $of_dn);

	sub rm_special_chars {
		my $string = shift;
		$string =~ tr/a-zA-Z0-9\.\-_ //dc;

		return($string);
	}

	push(@tags, rm_special_chars(${$$tags_ref{albumartist}}));
	push(@tags, rm_special_chars(${$$tags_ref{album}}));
	push(@tags, rm_special_chars(${$$tags_ref{discnumber}}));
	push(@tags, rm_special_chars(${$$tags_ref{tracknumber}}));
	push(@tags, rm_special_chars(${$$tags_ref{title}}));

	$of_dn = join('/', $ENV{HOME}, $ext, $tags[0], $tags[1]);

	unless (-d $of_dn) {
		make_path($of_dn) or warn "Can't make_path '$of_dn': $!";
	}

	$of_bn = sprintf('%d-%02d. %s.%s', $tags[2], $tags[3], $tags[4], $ext);

	$of = $of_dn . '/' . $of_bn;

	if (-f $of) {
		say $of . ': already exists';
		threads->exit();
	}

	return($of);
}

# The 'decode' subroutine decodes FLAC files to WAV / PCM, and stores
# them in RAM.
sub decode {
	my $fn = shift;

	my($size);

# Enable slurp mode.
	local $/;

	open(my $flac, '-|:raw', 'flac', '--silent', '--stdout',
	'--decode', $fn) or die "Can't run 'flac': $!";
	$pcm{$fn} = (<$flac>);
	close($flac) or die "Couldn't close 'flac': $!";

	$size = length($pcm{$fn});

	{ lock($file_stack);
	$file_stack += $size; }

	return($size);
}

# The 'lame' subroutine encodes FLAC files to MP3.
sub lame {
	my $tid = threads->tid();

	while (my($if, $size) = $files_q->dequeue(2)) {
		my @opts_tmp = @opts;

		my(%tags_ref, $tag_tmp);

		mk_refs($if, \%tags_ref);

		my $of = name($if, 'mp3', \%tags_ref);

		$tag_tmp = ${$tags_ref{artist}};
		push(@opts_tmp, ('--ta', $tag_tmp));

		$tag_tmp = ${$tags_ref{album}};
		push(@opts_tmp, ('--tl', $tag_tmp));

		$tag_tmp = ${$tags_ref{tracknumber}};
		push(@opts_tmp, ('--tn', $tag_tmp));

		$tag_tmp = ${$tags_ref{title}};
		push(@opts_tmp, ('--tt', $tag_tmp));

		${$tags_ref{date}} =~ m/$regex{date}/;

		if (length($1)) {
			$tag_tmp = $1;
			push(@opts_tmp, ('--ty', $tag_tmp));
		}

		push(@opts_tmp, '-');
		push(@opts_tmp, $of);

		say $tid . ' ' . $of . ': encoding...';

		open(my $lame, '|-:raw', @opts_tmp)
		or die "Can't run 'lame': $!";
		print $lame $pcm{$if};
		close($lame) or die "Couldn't close 'lame': $!";

		{ lock(%pcm);
		lock($file_stack);
		delete($pcm{$if});
		$file_stack -= $size; }
	}
}

# The 'aac' subroutine encodes FLAC files to AAC.
sub aac {
	my $tid = threads->tid();

	while (my($if, $size) = $files_q->dequeue(2)) {
		my @opts_tmp = @opts;

		my(%tags_ref, $tag_tmp);

		mk_refs($if, \%tags_ref);

		my $of = name($if, 'm4a', \%tags_ref);

		$tag_tmp = 'artist' . '=' . ${$tags_ref{artist}};
		push(@opts_tmp, ('-metadata', $tag_tmp));

		$tag_tmp = 'album' . '=' . ${$tags_ref{album}};
		push(@opts_tmp, ('-metadata', $tag_tmp));

		$tag_tmp = 'tracknumber' . '=' . ${$tags_ref{tracknumber}};
		push(@opts_tmp, ('-metadata', $tag_tmp));

		$tag_tmp = 'title' . '=' . ${$tags_ref{title}};
		push(@opts_tmp, ('-metadata', $tag_tmp));

		${$tags_ref{date}} =~ m/$regex{date}/;

		if (length($1)) {
			$tag_tmp = 'date' . '=' . $1;
			push(@opts_tmp, ('-metadata', $tag_tmp));
		}

		push(@opts_tmp, $of);

		say $tid . ' ' . $of . ': encoding...';

		open(my $ffmpeg, '|-:raw', @opts_tmp)
		or die "Can't run 'ffmpeg': $!";
		print $ffmpeg $pcm{$if};
		close($ffmpeg) or die "Couldn't close 'ffmpeg': $!";

		{ lock(%pcm);
		lock($file_stack);
		delete($pcm{$if});
		$file_stack -= $size; }
	}
}

# The 'vorbis' subroutine encodes FLAC files to Ogg Vorbis.
sub vorbis {
	my $tid = threads->tid();

	while (my($if, $size) = $files_q->dequeue(2)) {
		my @opts_tmp = @opts;

		my(%tags_ref, $tag_tmp);

		mk_refs($if, \%tags_ref);

		my $of = name($if, 'ogg', \%tags_ref);

		push(@opts_tmp, ('-o', $of));

		$tag_tmp = 'artist' . '=' . ${$tags_ref{artist}};
		push(@opts_tmp, ('-c', $tag_tmp));

		$tag_tmp = 'album' . '=' . ${$tags_ref{album}};
		push(@opts_tmp, ('-c', $tag_tmp));

		$tag_tmp = 'tracknumber' . '=' . ${$tags_ref{tracknumber}};
		push(@opts_tmp, ('-c', $tag_tmp));

		$tag_tmp = 'title' . '=' . ${$tags_ref{title}};
		push(@opts_tmp, ('-c', $tag_tmp));

		${$tags_ref{date}} =~ m/$regex{date}/;

		if (length($1)) {
			$tag_tmp = 'date' . '=' . $1;
			push(@opts_tmp, ('-c', $tag_tmp));
		}

		push(@opts_tmp, '-');

		say $tid . ' ' . $of . ': encoding...';

		open(my $oggenc, '|-:raw', @opts_tmp)
		or die "Can't run 'oggenc': $!";
		print $oggenc $pcm{$if};
		close($oggenc) or die "Couldn't close 'oggenc': $!";

		{ lock(%pcm);
		lock($file_stack);
		delete($pcm{$if});
		$file_stack -= $size; }
	}
}

# The 'opus' subroutine encodes FLAC files to Opus.
sub opus {
	my $tid = threads->tid();

	while (my($if, $size) = $files_q->dequeue(2)) {
		my @opts_tmp = @opts;

		my(%tags_ref, $tag_tmp);

		mk_refs($if, \%tags_ref);

		my $of = name($if, 'opus', \%tags_ref);

		$tag_tmp = 'artist' . '=' . ${$tags_ref{artist}};
		push(@opts_tmp, ('--comment', $tag_tmp));

		$tag_tmp = 'album' . '=' . ${$tags_ref{album}};
		push(@opts_tmp, ('--comment', $tag_tmp));

		$tag_tmp = 'tracknumber' . '=' . ${$tags_ref{tracknumber}};
		push(@opts_tmp, ('--comment', $tag_tmp));

		$tag_tmp = 'title' . '=' . ${$tags_ref{title}};
		push(@opts_tmp, ('--comment', $tag_tmp));

		${$tags_ref{date}} =~ m/$regex{date}/;

		if (length($1)) {
			$tag_tmp = 'date' . '=' . $1;
			push(@opts_tmp, ('--comment', $tag_tmp));
		}

		push(@opts_tmp, '-');
		push(@opts_tmp, $of);

		say $tid . ' ' . $of . ': encoding...';

		open(my $opusenc, '|-:raw', @opts_tmp)
		or die "Can't run 'opusenc': $!";
		print $opusenc $pcm{$if};
		close($opusenc) or die "Couldn't close 'opusenc': $!";

		{ lock(%pcm);
		lock($file_stack);
		delete($pcm{$if});
		$file_stack -= $size; }
	}
}

say "\n" . 'Starting threads!' . "\n";

push(@threads, threads->create(\&files2queue));

foreach (1 .. $cores) {
	if ($mode eq 'mp3') {
		push(@threads, threads->create(\&lame));

		next;
	}

	if ($mode eq 'aac') {
		push(@threads, threads->create(\&aac));

		next;
	}

	if ($mode eq 'ogg') {
		push(@threads, threads->create(\&vorbis));

		next;
	}

	if ($mode eq 'opus') {
		push(@threads, threads->create(\&opus));

		next;
	}
}

foreach my $thr (@threads) { $thr->join(); }

say "\n" . 'Done!' . "\n";
