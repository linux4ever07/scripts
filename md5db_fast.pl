#!/usr/bin/perl

# This script uses lists of MD5 hashes ('md5.db' files) to recursively
# keep track of changes in a directory.

# The script is multithreaded and keeps 1 thread for reading files into
# RAM, and a number of threads (based on CPU count) to process the
# files.

# Mechanical drives are slow, while RAM is much faster, so the reason
# for processing the files this way is to maximize performance. It
# guarantees that the hard drive only has to read 1 file at a time, even
# though multiple files will be processed at a time.

# File systems like Btrfs or ZFS already have checksumming built in.
# This script is meant for file systems that lack that capability.

# There's also this:
# https://en.wikipedia.org/wiki/Inotify

# The script checks FLAC files using 'flac' and 'metaflac', so if you
# don't have those commands installed, only non-FLAC files will be
# checked.

use 5.34.0;
use strict;
use warnings;
use diagnostics;
use Cwd qw(abs_path);
use Digest::MD5 qw(md5_hex);
use IO::Handle qw(autoflush);
use File::Basename qw(basename dirname);

use threads qw(yield);
use threads::shared;
use Thread::Queue;
use POSIX qw(SIGINT);

my(@lib, @run, $mode);

# Array for storing the actual arguments used by the script internally.
# Might be useful for debugging.
my @cmd = (basename($0));

# Clear screen command.
my $clear = `clear && echo`;

# Get the number of available CPU cores. Add 1 to this number, which
# will lead to an extra thread being created, maximizing performance.
chomp(my $cores = `grep -c '^processor' '/proc/cpuinfo'`);
$cores++;

# Check if the necessary commands are installed to test FLAC files.
chomp(my @flac_req = (`command -v flac metaflac 2>&-`));

# Name of database file.
my $db = 'md5.db';

# Path to and name of log file to be used for logging.
my $log_fn = $ENV{HOME} . '/' . 'md5db.log';

# Regex used for skipping dotfiles in home directories.
my $dotskip = qr(^/home/[[:alnum:]]+/\.);

# Delimiter used for database.
my $delim = "\t\*\t";

# Creating a variable which sets a limit on the total number of bytes
# that can be read into RAM at once. If you have plenty of RAM, it's
# safe to increase this number. It will improve performance.
my $disk_size = 1000000000;

# Creating a few shared variables.
# * @threads stores threads that are created.
# * @md5dbs stores 'md5.db' files.
# * %md5h is the database hash.
# * %file_contents stores the contents of files.
# * %large stores the names of files that are too big to fit in RAM.
# * %gone stores the names and MD5 hashes of possibly deleted files.
# * $files_n stores the number of files that have been processed.
# * $stopping is used to stop threads, and quit the script.
# * $file_stack tracks the amount of file data currently in RAM.
# * $busy is used to pause other threads when a thread is busy.
my(@threads, @md5dbs) :shared;
my(%md5h, %file_contents, %large, %gone) :shared;
my $files_n :shared = 0;
my $stopping :shared = 0;
my $file_stack :shared = 0;
my $busy :shared = 0;

# Create files queue, and log queue.
my $files_q = Thread::Queue->new();
my $log_q = Thread::Queue->new();

# Creating a custom POSIX signal handler. First we create a shared
# variable that will work as a SIGINT switch. Then we define the handler
# subroutine.
POSIX::sigaction(SIGINT, POSIX::SigAction->new(\&handler))
or die "Error setting SIGINT handler: $!";
my $saw_sigint :shared = 0;

sub handler {
	lock($saw_sigint);
	$saw_sigint = 1;
	lock($stopping);
	$stopping = 1;
}

# Duplicate STDOUT and STDERR as a regular file handles.
open(my $stdout, ">&STDOUT") or die "Can't duplicate STDOUT: $!";
open(my $stderr, ">&STDERR") or die "Can't duplicate STDERR: $!";

# Subroutine for printing usage instructions.
sub usage {
	say "
Usage: $cmd[0] [options] [directory 1] .. [directory N]

	Options:

-double
	Check database for duplicate files.

-import
	Import MD5 hashes to database from already existing \*.MD5 files.

-index
	Index files and add them to database.

-test
	Test the MD5 hashes of the files in database to see if they've
	changed.
";

	exit;
}

# Go through the arguments passed to the script by the user.
given (my $arg = shift(@ARGV)) {
# When '-double', set script mode to 'double', and call the md5double
# subroutine later.
	when ('-double') { push(@cmd, $arg); $mode = 'double'; }
# When '-import', set script mode to 'import', and call the md5import
# subroutine later.
	when ('-import') { push(@cmd, $arg); $mode = 'import'; }
# When '-index', set script mode to 'index', and call the md5index
# subroutine later.
	when ('-index') { push(@cmd, $arg); $mode = 'index'; }
# When '-test', set the script mode to 'test', and call the md5test
# subroutine later.
	when ('-test') { push(@cmd, $arg); $mode = 'test'; }
	default { usage(); }
}

# If the remaining arguments are directories, store them in the @lib
# array.
while (my $arg = shift(@ARGV)) {
	if (-d $arg) {
		my $dn = abs_path($arg);
		push(@lib, $dn);
		push(@cmd, $dn);
	} else { usage(); }
}

# Print usage instructions if @lib array is empty.
if (! scalar(@lib)) { usage(); }

# Subroutine for when the script needs to quit, either cause of being
# finished, or SIGINT has been triggered.
sub iquit {
	while (! $stopping) { sleep(0.5); }

# Depending on whether the script is finished or SIGINT has been tripped
# we handle the closing of threads differently. If SIGINT has been
# tripped and a thread is still running / active, sleep for 1 second and
# then detach the thread without waiting for it to finish. The @threads
# array is locked, to make sure that the main thread has finished
# starting all the threads, before we start closing them. We start
# looping through the array at element 2, as element 0 is this thread
# (iquit), and element 1 is the logger thread.
	{
		lock(@threads);

		for (my $i = 2; $i < scalar(@threads); $i++) {
			my $tid = $threads[$i];
			my $thr = threads->object($tid);

			if ($saw_sigint) {
				if ($thr->is_running()) {
					sleep(1);

					$thr->detach();
					next;
				}
			}

			$thr->join();
		}
	}

# Delete empty elements from database hash.
	foreach my $fn (keys(%md5h)) {
		if ($md5h{$fn} eq '1') {
			delete($md5h{$fn});
		}
	}

# Print missing files, and close the log file.
	p_gone();
	$log_q->enqueue('end', 'end');
	$log_q->end();

# Close logger thread.
	my $thr_logger = threads->object($threads[1]);
	$thr_logger->join();

# Print database hash to database file.
	hash2file();
}

# Subroutine for putting files in the queue, and loading them into RAM.
sub files2queue {
	my(@files);

	if ($mode eq 'index') {
# If MD5 hash of file name is already in database, skip it.
# If file is a FLAC file, then enqueue it directly instead of reading it
# into RAM.
		foreach my $fn (sort(keys(%md5h))) {
			if ($md5h{$fn} eq '1') {
				if ($fn =~ /.flac$/i) { $files_q->enqueue($fn); next; }

				push(@files, $fn);
			}
		}
	}

	if ($mode eq 'test') {
		foreach my $fn (sort(keys(%md5h))) {
			if ($md5h{$fn} ne '1') {
				push(@files, $fn);
			}
		}
	}

# This loop reads the files into RAM, if there's enough RAM available.
# If the file is larger than the limit set in $disk_size, it will
# instead be added to the %large hash. The files in that hash will be
# processed one at a time, since they have to be read directly from the
# hard drive.
	foreach my $fn (@files) {
		my $size = (stat($fn))[7];

		if (! length($size)) { next; }

		if ($size <= $disk_size) {
			my $free = $disk_size - $file_stack;

			while ($size > $free) {
				yield();
				$free = $disk_size - $file_stack;
			}

			$file_contents{$fn} = 1;

			open(my $read_fn, '< :raw', $fn) or die "Can't open '$fn': $!";
			sysread($read_fn, $file_contents{$fn}, $size);
			close($read_fn) or die "Can't close '$fn': $!";

			{ lock($file_stack);
			$file_stack += length($file_contents{$fn}); }

			$files_q->enqueue($fn);
		} else { $large{$fn} = 1; }
	}

# Put all the large files in the queue, after all the smaller files are
# done being processed. This is to prevent multiple files from being
# read from the hard drive at once, slowing things down.
	if (keys(%large)) {
		while ($file_stack > 0) {
			say $file_stack . ' > ' . '0';
			yield();
		}

		foreach my $fn (sort(keys(%large))) { $files_q->enqueue($fn); }
	}

	$files_q->end();

# If there's still files in the queue left to be processed, and SIGINT
# has not been triggered, wait for the other threads to empty the queue.
	while ($files_q->pending() and ! $saw_sigint) { sleep(0.5); }

# We're using this subroutine / thread to indicate to the other threads
# when to quit, since this is where we create the file queue.
	{ lock($stopping);
	$stopping = 1; }
}

# Subroutine for managing the log file.
# It takes 2 arguments:
# (1) switch (start gone corr diff end)
# (2) file name / directory name
sub logger {
	my(%err, @outs, $now);

# Open file handle for the log file
	open(my $log, '>>', $log_fn) or die "Can't open '$log_fn': $!";

# Make the $log file handle unbuffered for instant logging.
	$log->autoflush(1);

	while (my @args = ($log_q->dequeue(2))) {
# When log is opened.
		if ($args[0] eq 'start') {
# Storing the current time in $now.
			$now = localtime(time);

			say $log "
**** Logging started on $now ****

Running script in \'$mode\' mode on:

$args[1]
";
			next;
		}

# When file has been deleted or moved.
		if ($args[0] eq 'gone') {
			$err{$args[1]} = 'has been (re)moved.';
			next;
		}

# When file has been corrupted.
		if ($args[0] eq 'corr') {
			$err{$args[1]} = 'has been corrupted.';
			next;
		}

# When file has been changed.
		if ($args[0] eq 'diff') {
			$err{$args[1]} = 'doesn\'t match the hash in database.';
			next;
		}

# When done or interrupted, to close the log.
# If errors occurred print the %err hash.
# Either way, print number of files processed.
		if ($args[0] eq 'end') {
# Storing the filehandles used to print messages in @outs array.
			@outs = ($stdout, $log);

# When the script is interrupted by user pressing ^C, say so in both
# STDERR and the log.
			if ($saw_sigint) {
				$outs[0] = $stderr;

				foreach my $out (@outs) {
					say $out 'Interrupted by user!' . "\n";
				}
			}

			if (! keys(%err)) {
				foreach my $out (@outs) {
					say $out 'Everything is OK!' . "\n";
				}
			} else {
				$outs[0] = $stderr;

				foreach my $out (@outs) {
					say $out 'Error(s) occurred!' . "\n";
				}

				foreach my $fn (sort(keys(%err))) {
					foreach my $out (@outs) {
						say $out $fn . "\n\t" . $err{$fn} . "\n";
					}
				}
			}

			if (length($files_n)) {
				foreach my $out (@outs) {
					say $out $files_n . ' file(s) were tested.' . "\n";
				}
			}

# Storing the current time in $now.
			$now = localtime(time);

			say $log '**** Logging ended on ' . $now . ' ****' . "\n";
			close $log or die "Can't close '$log': $!";
		}
	}
}

# Subroutine for initializing database hash.
# This is the first subroutine that will be executed, and all others
# depend upon it.
sub init_hash {
# Get all the file names in the current directory.
	getfiles();

# Import hashes from every database file found in the search path.
	foreach my $db (@md5dbs) { file2hash($db); }

# Clears the screen, thereby scrolling past database file print.
	print $clear;
}

# Subroutine for when database file is empty, or doesn't exist.
sub if_empty {
	foreach my $fn (keys(%md5h)) {
		if ($md5h{$fn} ne '1') { return; }
	}

	say "
No database file. Run the script in 'index' mode first to index files.
";

	exit;
}

# Subroutine for finding all files in the current directory.
sub getfiles {
	my(@lines);

	open(my $find, '-|', 'find', '.', '-type', 'f', '-name', '*', '-nowarn')
	or die "Can't run 'find': $!";
	chomp(@lines = (<$find>));
	close($find) or die "Can't close 'find': $!";

	foreach my $fn (@lines) {
# If the file name matches "$HOME/.*", then skip it. Dotfiles in a
# user's home directory are usually configuration files for the desktop
# and various applications. These files change often and will therefore
# clog the log file created by this script, making it hard to read.
		if (abs_path($fn) =~ m($dotskip)) { next; }

		$fn =~ s(^\./)();

		if (-f $fn and -r $fn) {
			my $bn = basename($fn);

# If file name isn't a database file, add it to databes hash.
# Precreating elements in database hash, to prevent threads from
# stepping over each other later.
			if ($bn ne $db) {
				$md5h{$fn} = 1;
# If file name is a database file, add it to @md5dbs.
			} elsif ($bn eq $db) { push(@md5dbs, $fn); }
		}
	}
}

# Subroutine for reading database files into database hash.
# It takes 1 argument:
# (1) file name
sub file2hash {
	my $db = shift;
	my $dn = dirname($db);
	my($fn, $hash, @lines);

# The format string which is used for parsing database file.
	my $format = qr/^(.*)\Q$delim\E([[:alnum:]]{32})$/;

# Open database file and read it into the @lines array.
	open(my $md5db_in, '<', $db) or die "Can't open '$db': $!";
	foreach my $line (<$md5db_in>) {
		$line =~ s/(\r){0,}(\n){0,}$//g;
		push(@lines, $line);
	}
	close($md5db_in) or die "Can't close '$db': $!";

# Loop through all the lines in database file and split them before
# storing in database hash. Also, print each line to STDOUT for debug
# purposes.
	foreach my $line (@lines) {
# If current line matches the proper database file format, continue.
		if ($line =~ /$format/) {
# Split the line into relative file name and MD5 hash.
			$fn = $1;
			$hash = $2;

# Add the full path to the file name, unless it's the current directory.
			if ($dn ne '.') { $fn = $dn . '/' . $fn; }

# If $fn is a real file.
			if (-f $fn) {
# If MD5 hash of file name is not already in database, add it and print
# a message.
				if ($md5h{$fn} eq '1') {
					$md5h{$fn} = $hash;
					say $fn . $delim . $hash;
# If file name is in database hash but the MD5 hash doesn't match, print
# to the log. This will most likely only be the case for any extra
# databases that are found in the search path given to the script.
				} elsif ($md5h{$fn} ne $hash) {
					$log_q->enqueue('diff', $fn);
				}
# If file name is not a real file, add $fn to %gone hash.
			} elsif (! -f $fn) {
				$gone{${fn}} = $hash;
			}
		}
	}
}

# Subroutine for printing database hash to database file.
sub hash2file {
# If database hash is empty, return from this subroutine, to keep from
# overwriting database file with nothing.
	if (! keys(%md5h)) { return; }

	my $of = 'md5' . '-' . int(rand(10000)) . '-' . int(rand(10000)) . '.db';

	open(my $md5db_out, '>', $of) or die "Can't open '$of': $!";
# Loops through all the keys in database hash and prints the entries
# (divided by the $delim variable) to database file.
	foreach my $fn (sort(keys(%md5h))) {
		say $md5db_out $fn . $delim . $md5h{$fn} . "\r";
	}
	close($md5db_out) or die "Can't close '$of': $!";

	rename($of, $db) or die "Can't rename file '$of': $!";
}

# Subroutine for finding duplicate files, by checking database hash.
sub md5double {
# Loop through the %md5h hash and save the checksums as keys in a new
# hash called %dups. Each of those keys will hold an anonymous array
# with the matching file names.
	my(%dups);

	foreach my $fn (keys(%md5h)) {
		if ($md5h{$fn} ne '1') {
			my $hash = $md5h{$fn};
			push(@{$dups{$hash}}, $fn);
		}
	}

# Loop through the %dups hash and print files that are identical, if
# any.
	foreach my $hash (keys(%dups)) {
		if (scalar(@{$dups{$hash}}) > 1) {
			say 'These files have the same hash (' . $hash . '):';
			foreach my $fn (@{$dups{$hash}}) { say $fn; }
			say '';
		}
	}
}

# Subroutine for parsing *.MD5 files, adding the file names and MD5
# hashes to database hash.
# It takes 1 argument:
# (1) file name
sub md5import {
	my $md5fn = shift;
	my $dn = dirname($md5fn);

	my($fn, $hash, @lines);

# The format string which is used for parsing the *.MD5 files.
	my $format = qr/^([[:alnum:]]{32})\s\*(.*)$/;

# Open the *.MD5 file and read its contents to the @lines array.
	open(my $md5_in, '<', $md5fn) or die "Can't open '$md5fn': $!";
	foreach my $line (<$md5_in>) {
		$line =~ s/(\r){0,}(\n){0,}$//g;
		push(@lines, $line);
	}
	close($md5_in) or die "Can't close '$md5fn': $!";

# Loop to check that the format of the *.MD5 file really is correct
# before proceeding.
	foreach my $line (@lines) {
# If format string matches the line(s) in the *.MD5 file, continue.
		if ($line =~ /$format/) {
# Split the line into MD5 hash and relative file name.
			$hash = lc($1);
			$fn = basename($2);

# Add the full path to the file name, unless it's the current directory.
			if ($dn ne '.') { $fn = $dn . '/' . $fn; }

# If $fn is a real file.
			if (-f $fn) {
# If MD5 hash of file name is not already in database, add it and print
# a message.
				if ($md5h{$fn} eq '1') {
					$md5h{$fn} = $hash;
					say $fn . ': done indexing';
# If file name is in database hash but the MD5 hash from the MD5 file
# doesn't match, print to the log.
				} elsif ($md5h{$fn} ne $hash) {
					$log_q->enqueue('diff', $fn);
				}
# If file name is not a real file, add $fn to %gone hash.
			} elsif (! -f $fn) {
				$gone{${fn}} = $hash;
			}
		}
	}
}

# Subroutine for clearing files from RAM, once they've been processed.
# It takes 1 argument:
# (1) file name
sub clear_stack {
	my $fn = shift;

	lock($file_stack);
	$file_stack -= length($file_contents{$fn});
	$file_contents{$fn} = 1;
}

# Subroutine for getting the MD5 hash of files.
# It takes 1 argument:
# (1) file name
sub md5sum {
	my $fn = shift;
	my($hash);

	if ($large{$fn}) {
		lock($busy);
		$busy = 1;

		open(my $read_fn, '< :raw', $fn) or die "Can't open '$fn': $!";
		$hash = Digest::MD5->new->addfile($read_fn)->hexdigest;
		close($read_fn) or die "Can't close '$fn': $!";

		$busy = 0;
	} else {
		$hash = md5_hex($file_contents{$fn});

		clear_stack($fn);
	}

	return $hash;
}

# Subroutine for getting the MD5 hash of FLAC files. Index by getting
# the MD5 hash from reading the metadata using 'metaflac', and test with
# 'flac'.
sub md5flac {
	my $fn = shift;
	my($hash);

	if (scalar(@flac_req) != 2) { return; }

	chomp($hash = `metaflac --show-md5sum "$fn" 2>&-`);

	if ($? != 0 and $? != 2) {
		$log_q->enqueue('corr', $fn);
		return;
	}

	if ($mode eq 'test') {
		if ($large{$fn}) {
			lock($busy);
			$busy = 1;

			system('flac', '--totally-silent', '--test', $fn);

			$busy = 0;
		} else {
			open(my $flac_test, '|-', 'flac', '--totally-silent', '--test', '-')
			or die "Can't open 'flac': $!";
			print $flac_test $file_contents{$fn};
			close($flac_test);

			clear_stack($fn);
		}

		if ($? != 0 and $? != 2) {
			$log_q->enqueue('corr', $fn);
			return;
		}
	}

	return $hash;
}

# Subroutine to index the files (i.e. calculate and store the MD5 hashes
# in database hash).
sub md5index {
	my $tid = threads->tid();
	my($tmp_md5);

# Loop through the thread queue.
	while (my $fn = $files_q->dequeue()) {
		if ($saw_sigint) { last; }

		if ($fn =~ /.flac$/i) { $tmp_md5 = md5flac($fn); }
		else { $tmp_md5 = md5sum($fn); }

		if (! length($tmp_md5)) { next; }

		$md5h{$fn} = $tmp_md5;

		say $tid . ' ' . $fn . ': done indexing (' . $file_stack . ')';

		{ lock($files_n);
		$files_n++; }
	}
}

# Subroutine for testing if the MD5 hashes in database file are correct
# (i.e. have changed or not).
sub md5test {
	my $tid = threads->tid();
	my($tmp_md5, $old_md5, $new_md5);

# Loop through the thread queue.
	while (my $fn = $files_q->dequeue()) {
		if ($saw_sigint) { last; }

		if ($fn =~ /.flac$/i) { $tmp_md5 = md5flac($fn); }
		else { $tmp_md5 = md5sum($fn); }

		if (! length($tmp_md5)) { next; }

		$new_md5 = $tmp_md5;
		$old_md5 = $md5h{$fn};

		say $tid . ' ' . $fn . ': done testing (' . $file_stack . ')';

# If the new MD5 hash doesn't match the one in database hash, log it and
# replace the old MD5 hash in the hash with the new one.
		if ($new_md5 ne $old_md5) {
			$log_q->enqueue('diff', $fn);
			$md5h{$fn} = $new_md5;
		}

		{ lock($files_n);
		$files_n++; }
	}
}

# Subroutine for figuring out which files have gone missing. If still
# existing files have identical MD5 hashes to those that are in %gone,
# then those file names will not be printed. The idea is that certain
# files may just have been renamed, or duplicates exist. Only print the
# files that are actually gone.
sub p_gone {
# If %gone is empty, return from this subroutine.
	if (! keys(%gone)) { return; }

	my(%gone_tmp);

# Translates the %gone hash to the %gone_tmp hash / array. We need to do
# it in this complicated way because 'threads::shared' has no support
# for hashes within hashes and arrays within arrays. That's why the
# global variables are only simple arrays, and we translate them to a
# hash / array here (in this subroutine).
	foreach my $fn (keys(%gone)) {
		my $hash = $gone{${fn}};
		push(@{$gone_tmp{$hash}}, $fn);
	}

# Loops through the %md5h hash and deletes every matching MD5 hash from
# the %gone_tmp hash / array.
	foreach my $fn (keys(%md5h)) {
		my $hash = ${md5h{$fn}};
		if ($gone_tmp{${hash}}) { delete($gone_tmp{${hash}}); }
	}

# Logs all missing files.
	foreach my $hash (keys(%gone_tmp)) {
		foreach my $fn (@{$gone_tmp{$hash}}) {
			$log_q->enqueue('gone', $fn);
		}
	}
}

# The 'iquit' and 'logger' threads need to be started first, as the
# script relies on them being the 2 first elements in the @threads
# array. If script mode is either 'index' or 'test', we'll start as
# many threads as the available number of CPUs. Unless script mode is
# either of those, don't start the 'files2queue' thread, as it's not
# needed. Also, note that 'files2queue' needs to be started after
# database hash has been initialized. Otherwise it will have nothing to
# work with.
push(@run, \&iquit);
push(@run, \&logger);

given ($mode) {
	when ('index') {
		push(@run, \&files2queue);
		push(@run, ((\&md5index) x $cores));
	}
	when ('test') {
		push(@run, \&files2queue);
		push(@run, ((\&md5test) x $cores));
	}
}

# This loop is where the actual action takes place (i.e. where all the
# subroutines get called from).
foreach my $dn (@lib) {
# Change into $dn.
	chdir($dn) or die "Can't change into '$dn': $!";

# Initialize database hash.
	init_hash();

	if ($mode ne 'import' and $mode ne 'index') { if_empty(); }

# Start logging.
	$log_q->enqueue('start', $dn);

# Start threads.
	{
		lock(@threads);

		foreach (@run) {
			my $thr = threads->create($_);
			push(@threads, $thr->tid());
		}
	}

	given ($mode) {
# Find duplicate files in database.
		when ('double') {
			md5double();
		}
# Import *.MD5 files to database.
		when ('import') {
			foreach my $fn (sort(keys(%md5h))) {
				if ($fn =~ /.md5$/i) { md5import($fn); }
			}
		}
	}

# If script mode is not 'index' or 'test', set the $stopping variable
# here, so the script can quit. Otherwise, the 'files2queue' thread is
# responsible for setting that variable.
	if ($mode ne 'index' and $mode ne 'test') {
		lock($stopping);
		$stopping = 1;
	}

# Since the 'iquit' subroutine / thread is in charge of joining threads,
# and finishing things up, all we have to do here is to join the 'iquit'
# thread.
	my $thr_iquit = threads->object($threads[0]);
	$thr_iquit->join();

# If SIGINT has been tripped, break this loop.
	if ($saw_sigint) { last; }

# Resets all the global / shared variables, making them ready for the
# next iteration of this loop. In case the user specified more than one
# directory as argument.
	$files_q = Thread::Queue->new();
	$log_q = Thread::Queue->new();

	@threads = ();
	@md5dbs = ();
	%md5h = ();
	%file_contents = ();
	%large = ();
	%gone = ();
	$files_n = 0;
	$stopping = 0;
	$file_stack = 0;
	$busy = 0;
}
