#!/usr/bin/perl
# This script uses lists of MD5 hashes ('md5.db' files) to recursively
# keep track of changes in a directory.

# The script checks FLAC files using 'flac' and 'metaflac', so if you
# don't have those commands installed, only non-FLAC files will be
# checked.

use 5.34.0;
use strict;
use warnings;
# use feature 'unicode_strings';
use Cwd qw(abs_path cwd);
use Digest::MD5 qw(md5_hex);
use IO::Handle qw(autoflush);
use File::Basename qw(basename dirname);
# use File::Slurp qw(read_file);
use diagnostics;

use threads qw(yield);
use threads::shared;
use Thread::Queue;
use Thread::Semaphore;
# use Fcntl qw(:flock);
use POSIX qw(SIGINT);
use POSIX qw(ceil);

# Create the thread queue.
my $q = Thread::Queue->new();

# Get the number of available CPU cores.
chomp(my $cores = `grep -c ^processor /proc/cpuinfo`);

# Check if the necessary commands are installed to test FLAC files.
chomp(my @flac_req = ( `command -v flac metaflac 2>&-` ));

my (@lib, $mode);

# Path to and name of log file to be used for logging.
my $logf = $ENV{HOME} . '/' . 'md5db.log';

# Regex used for skipping dot files and directories in home directories.
my $dotskip = qr(^/home/[[:alnum:]]+/\.);

# Delimiter used for database.
my $delim = "\t\*\t";

# Array for storing the actual arguments used by the script internally.
# Might be useful for debugging.
my @cmd = (basename($0));

# Name of database file.
my $db = 'md5.db';

# Clear screen command.
my $clear = `clear && echo`;

# Creating a hash that will store the names of files that are too big to
# fit into RAM. We'll process them last.
my %large :shared;

# Creating the %gone_tmp hash that will store the names and hashes of
# possibly deleted files.
my %gone_tmp :shared;

# Creating a few shared variables. %err will be used for errors. $n will
# be used to count the number of files processed. %md5h is the database
# hash. %file_contents will be used to store the contents of files.
# $stopping will be used to stop the threads if the script is
# interrupted. $file_stack will be used to track the amount of file data
# currently in RAM. $busy will be used to pause other threads when a
# thread is busy. $disk_size will be used to limit the amount of file
# data that can be read into RAM.
my %err :shared;
my $n :shared = 0;
my %md5h :shared;
my %file_contents :shared;
my $stopping :shared = 0;
my $file_stack :shared = 0;
my $busy :shared = 0;

my $disk_size = 1000000000;

# This will be used to control access to the logger subroutine.
my $semaphore = Thread::Semaphore->new();

POSIX::sigaction(SIGINT, POSIX::SigAction->new(\&handler))
or die "Error setting SIGINT handler: $!\n";

# Creating a custom POSIX signal handler. First we create a shared
# variable that will work as a SIGINT switch. Then we define the handler
# subroutine. Each subroutine to be used for starting threads will have
# to take notice of the state of the $saw_sigint variable.
my $saw_sigint :shared = 0;
sub handler { $saw_sigint = 1; }

# Open file handle for the log file
open(my $LOG, '>>', $logf) or die "Can't open '$logf': $!";

# Make the $LOG file handle unbuffered for instant logging.
$LOG->autoflush(1);

# Duplicate STDERR as a regular file handle.
open(my $SE, ">&STDERR") or die "Can't duplicate STDERR: $!";

# Subroutine for printing usage instructions.
sub usage {
	say "
Usage: $cmd[0] [options] [directory 1] .. [directory N]

	-help Print this help message.

	-double Check database for files that have identical
	hashes.

	-import Import MD5 sums to the database from already existing
	\*.MD5 files in each directory.

	-index Index new files in each directory.

	-test Test the MD5 sums of the files in the database to see if
	they've changed.
";

	exit;
}

# This loop goes through the argument list as passed to the script
# by the user when ran.
foreach my $arg (@ARGV) {
# If argument starts with a dash '-', interpret it as an option.
	if ($arg =~ /^-/) {
		given ($arg) {
# When '-double', set script mode to 'double', and call the md5double
# subroutine later.
			when (/^-double$/) {
				if (! length($mode)) { push(@cmd, $arg); $mode = 'double'; }
			}

# When '-import', set script mode to 'import', and call the md5import
# subroutine later.
			when (/^-import$/) {
				if (! length($mode)) { push(@cmd, $arg); $mode = 'import'; }
			}

# When '-help', set script mode to 'help', and print usage instructions
# later.
			when (/^-help$/) {
				if (! length($mode)) { push(@cmd, $arg); $mode = 'help'; }
			}

# When '-index', set script mode to 'index', and call the md5index
# subroutine later.
			when (/^-index$/) {
				if (! length($mode)) { push(@cmd, $arg); $mode = 'index'; }
			}

# When '-test', set the script mode to 'test', and call the md5test
# subroutine later.
			when (/^-test$/) {
				if (! length($mode)) { push(@cmd, $arg); $mode = 'test'; }
			}
		}
# If argument is a directory, include it in the @lib array.
	} else {
		if (-d $arg) {
			my $dn = abs_path($arg);
			push(@lib, $dn);
			push(@cmd, $dn);
		}
	}
}

# If no switches were used, print usage instructions.
if (! scalar(@lib) or ! length($mode) or $mode eq 'help') { usage(); }

# say "@cmd\n";

# Subroutine is for loading files into RAM.
sub file2ram {
	my $fn = shift;
	my $size = (stat($fn))[7];

	if (! length($size)) { return(); }

	if ($size < $disk_size) {
		open(my $read_fn, '<:raw', $fn) or die "Can't open '$fn': $!";
		sysread($read_fn, $file_contents{$fn}, $size);
		close($read_fn) or die "Can't close '$fn': $!";

		{ lock($file_stack);
		$file_stack += length($file_contents{$fn}); }

		$q->enqueue($fn);
	} elsif ($size) {
		$large{$fn} = 1;
	}
}

# This subroutine is called if something goes wrong and the script needs
# to quit prematurely.
sub iquit {
	my $tid = threads->tid();
	if ($tid == 1) {
# Set the $stopping variable to let the threads know it's time to stop,
# and sleep for 1 second so they'll have time to quit.
		{ lock($stopping);
		$stopping = 1; }

		sleep(1);

# Write the hash to the database file and write to the log.
		hash2file();
		logger('int', $n);

# Detaching the threads so Perl will clean up after us.
		foreach my $t (threads->list()) { $t->detach(); }
		exit;
# If the thread calling this subroutine isn't thread 0/1, yield until
# $stopping is set.
	} elsif ($tid > 1) { while (!$stopping) { yield(); } }
}

# Subroutine for controlling the log file Applying a semaphore so
# multiple threads won't try to access it at once, just in case ;-)
# It takes 2 arguments:
# (1) switch
# (2) file name / file size
sub logger {
	$semaphore->down();

	my $sw = shift;
	my($arg, @fn, $n);

# Creating a variable to hold the current time.
	my $now = localtime(time);

# Array of accepted switches to this subroutine
	my @larg = qw{start int gone corr diff end};

# Loop through all the arguments passed to this subroutine Perform
# checks that decide which variable the arguments are to be assigned to.
	while (@_) {
		$arg = shift(@_);

# If $arg is a number assign it to $n, if it's a file add it to @fn.
		if ($sw eq 'int' or $sw eq 'end') { $n = $arg; }
		else { push(@fn, $arg); }
	}

	given ($sw) {
# Starts writing the log.
		when ('start') {
			say $LOG "\n" . '**** Logging started on ' . $now . ' ****'
			. "\n\n" . 'Running script in \'' . $mode . '\' mode on:' .
			"\n";
			foreach my $dn (@lib) { say $LOG $dn; }
			say $LOG "";
		}
# When the script is interrupted by user pressing ^C, say so in STDOUT,
# close the log.
		when ('int') {
			say "\n" . 'Interrupted by user!' . "\n\n" . $n .
			" file(s) were tested." . "\n" . '**** Logging ended on ' .
			$now . ' ****' . "\n";
			close $LOG or die "Can't close '$LOG': $!";
		}
# Called when file has been deleted or moved.
		when ('gone') {
			say $LOG $fn[0] . "\n\t" . 'has been (re)moved.' . "\n";
			$err{$fn[0]} = 'has been (re)moved.' . "\n";
		}
# Called when file has been corrupted.
		when ('corr') {
			say $LOG $fn[0] . "\n\t" . 'has been corrupted.' . "\n";
			$err{$fn[0]} = 'has been corrupted.' . "\n";
		}
		when ('diff') {
			say $LOG $fn[0] . "\n\t" .
			'doesn\'t match the hash in database.' . "\n";
			$err{$fn[0]} = 'doesn\'t match the hash in database.' .
			"\n";
		}
# Called when done, and to close the log.
# If no errors occurred write "Everything is OK!" to the log.
# If errors occurred print the %err hash.
# Either way, print number of files processed.
		when ('end') {
			if (! keys(%err)) {
				say $LOG "\n" . 'Everything is OK!' . "\n";
			} else {
				say "\n" . '**** Errors Occurred ****' . "\n";
				foreach my $fn (sort(keys(%err))) {
					say $SE $fn . "\n\t" . $err{$fn};
				}
			}

			say $LOG $n . ' file(s) were tested.' . "\n" if (length($n));
			say $LOG "\n" . '**** Logging ended on ' . $now . ' ****' .
			"\n";
			close $LOG or die "Can't close '$LOG': $!";
		}
	}

	$semaphore->up();
}

# Subroutine for reading a database file into the database hash. This is
# the first subroutine that will be executed and all others depend upon
# it, cause without it we don't have a database hash to work with.
sub file2hash {
	my $db = shift;
	my $dn = shift;

# The format string which is used for parsing the database file.
	my $format = qr/^.*\Q$delim\E[[:alnum:]]{32}$/;
	my (@dbfile, $md5db_in);

# Open the database file and read it into the @dbfile variable.
	open($md5db_in, '<', $db) or die "Can't open '$db': $!";
	foreach my $line (<$md5db_in>) {
		$line =~ s/(\r){0,}(\n){0,}$//g;
		push(@dbfile, $line);
	}
	close($md5db_in) or die "Can't close '$db': $!";

# Loop through all the lines in the database file and split them before
# storing in the database hash. Also, print each line to STDOUT for
# debug purposes.
	foreach my $line (@dbfile) {
# If current line matches the proper database file format, continue.
		if ($line =~ /$format/) {
# Split the line into relative file name, and MD5 sum.
# Also create another variable that contains the absolute file name.
			my ($rel_fn, $hash) = (split(/\Q$delim\E/, $line));
			my $abs_fn;
			if ($dn ne '.') { $abs_fn = $dn . '/' . $rel_fn; }
			else { $abs_fn = $rel_fn; }

# If $abs_fn is a real file and not already in the hash, continue.
			if (-f $abs_fn && ! length($md5h{$abs_fn})) {
				$md5h{$abs_fn} = $hash;
				say $abs_fn . $delim . $hash;

# If the file is in the database hash but the MD5 sum found in the
# database doesn't match the one in the hash, print to the log.

# This will most likely only be the case for any extra databases that
# are found in the search path given to the script.
			} elsif (-f $abs_fn && $md5h{$abs_fn} ne $hash) {
				logger('diff', $abs_fn);
# Saves the names of deleted or moved files in '%gone'.
			} elsif (! -f $abs_fn) {
				lock(%gone_tmp);
				$gone_tmp{${abs_fn}} = $hash;
			}
		}
	}

# Clears the screen, thereby scrolling past the database file print.
	print $clear;
}

# Subroutine for printing the database hash to the database file.
sub hash2file {
	my $md5db_out;

	open($md5db_out, '>', $db) or die "Can't open '$db': $!";
# Loops through all the keys in the database hash and prints the entries
# (divided by the $delim variable) to the database file.
	foreach my $k (sort(keys(%md5h))) {
		say $md5db_out $k . $delim . $md5h{$k} . "\r";
	}
	close($md5db_out) or die "Can't close '$db': $!";
}

# Subroutine for initializing the database hash, and the files array.
# The init_hash subroutine returns references.
# It takes 1 argument:
# (1) directory name
sub init_hash {
	my $dn = shift;

# Get all the file names in the path.
	my($files, $md5dbs) = getfiles($dn);

# But first import hashes from any databases found in the search path to
# avoid re-hashing them.
	if (scalar(@{$md5dbs})) {
		foreach my $db (@{$md5dbs}) {
			my $dn = dirname($db);
			file2hash($db, $dn);
		}
	}
	return($files, $md5dbs);
}

# Subroutine for when the database file is empty, or doesn't exist.
sub if_empty {
	if (! keys(%md5h)) {
		say 'No database file. Run the script in \'index\' mode first' .
		"\n" . 'to index the files.';
		exit;
	}
}

# Subroutine for finding files. Finds all the files inside the directory
# name passed to it, and processes the output before storing it in the
# @files array.
sub getfiles {
	my $dn = shift;
	my(@files, @md5dbs, @lines);

	open(my $find, '-|', 'find', $dn, '-type', 'f', '-name', '*', '-nowarn')
	or die "Can't run 'find': $!";
	chomp(@lines = (<$find>));
	close($find) or die "Can't close 'find': $!";

	foreach my $fn (@lines) {
# If the file name matches "$HOME/.*", then ignore it. Directories in
# the home-dir of a user are usually configuration files for the desktop
# and various applications. These files change often and will therefore
# clog the log file created by this script, making it hard to read.
		if ($fn =~ m($dotskip)) { next; }

# Using quotemeta operators here (\Q & \E) because Perl interprets the
# string as a regular expression when it's not.
		$fn =~ s(^\Q$dn\E/)();

		if (-f $fn) {
			my $bn = basename($fn);

			if ($bn ne $db) { push(@files, $fn); }
			elsif ($bn eq $db) { push(@md5dbs, $fn); }
		}
	}

	return(\@files, \@md5dbs);
}

# Subroutine for clearing files from RAM, once they've been processed.
# It takes 1 argument:
# 1) file name
sub clear_stack {
	my $fn = shift;

	{ lock($file_stack);
	$file_stack -= length($file_contents{$fn}); }

	{ lock(%file_contents);
	delete($file_contents{$fn}); }
}

# Subroutine for finding duplicate files, by checking the database hash.
sub md5double {
# Loop through the %md5h hash and save the checksums as keys in a new
# hash called %exists. Each of those keys will hold an anonymous array
# with the matching file names.
	my %exists;

	foreach my $fn (keys(%md5h)) {
		my $hash = $md5h{$fn};
		if (! scalar(@{$exists{${hash}}})) {
			$exists{${hash}}->[0] = $fn;
		} else {
			push(@{$exists{${hash}}}, $fn);
		}
	}

# Loop through the %exists hash and print files that are identical, if
# any.
	foreach my $hash (keys(%exists)) {
		if (scalar(@{$exists{${hash}}}) > 1) {
			say 'These files have the same hash (' . $hash . '):';
			foreach my $fn (@{$exists{${hash}}}) { say $fn; }
			say "";
		}
	}
}

# Subroutine for finding and parsing *.MD5 files, adding the hashes to
# the database hash and thereby also to the file. It takes 1 argument:
# (1) file name
sub md5import {
	my $md5fn = shift;

	my ($fn, $hash, @fields, @lines);

# The format string which is used for parsing the *.MD5 files.
	my $format = qr/^[[:alnum:]]{32}\s\*.*/;

# If the file extension is *.MD5 in either upper- or lowercase,
# continue.
	if ($md5fn =~ /.md5$/i) {
# Open the *.MD5 file and read its contents to the @lines array.
		open(my $md5, '<', $md5fn) or die "Can't open '$md5fn': $!";
		foreach my $line (<$md5>) {
			$line =~ s/(\r){0,}(\n){0,}$//g;
			push(@lines, $line);
		}
		close($md5) or die "Can't close '$md5fn': $!";

# Loop to check that the format of the *.MD5 file really is correct
# before proceeding.
		foreach my $line (@lines) {
# If format string matches the line(s) in the *.MD5 file, continue.
			if ($line =~ /$format/) {
# Split the line so that the hash and file name go into @fields array.
# After that strip the path (if any) of the file name, and prepend the
# path of the *.MD5 file to it instead. Store hash and file name in the
# $hash and $fn variables for readability.
				@fields = split(/\s\*/, $line, 2);
				my $path = dirname($md5fn);
				$hash = $fields[0];

				if ($path eq '.') { $fn = basename($fields[1]); }
				else { $fn = dirname($md5fn) . '/' . basename($fields[1]); }

# Unless file name already is in the database hash, print a message, add
# it to the hash.
				if (! length($md5h{$fn}) && -f $fn) {
					say $fn . "\n\t" . 'Imported MD5 sum from \'' .
					basename($md5fn) . '\'.' . "\n";

					$md5h{$fn} = $hash;

# If file name is not a real file, add $fn to %gone hash.. If file name
# is in database hash but the MD5 sum from the MD5 file doesn't match,
# print to the log.
				} elsif (! -f $fn) {
					lock(%gone_tmp);
					$gone_tmp{${fn}} = $hash;
				} elsif ($md5h{$fn} ne $hash) { logger('diff', $md5fn); }
			}
		}
	}
}

# Subroutine for getting the MD5 hash of a file.
# It takes 1 argument:
# (1) file name
sub md5sum {
	my $fn = shift;
	my $hash;

	while ($busy) { yield(); }

	if (! -r $fn) { next; }

# If the file name is a FLAC file, test it with 'flac'.
	if ($fn =~ /.flac$/i) {
		$hash = md5flac($fn);

		if ($mode eq 'test') {
			clear_stack($fn);
		}

		return $hash;
	}

	if ($large{$fn}) {
		lock($busy);
		$busy = 1;

		my $read_fn;

		open($read_fn, '<:raw', $fn) or die "Can't open '$fn': $!";
		$hash = Digest::MD5->new->addfile($read_fn)->hexdigest;
		close($read_fn) or die "Can't close '$fn': $!";

		$busy = 0;
	} else {
		$hash = md5_hex($file_contents{$fn});

		clear_stack($fn);
	}

	return $hash;
}

# Subroutine to index the files, i.e calculate and store the MD5 sums in
# the database hash/file.
sub md5index {
	my $tid = threads->tid();
	my $tmp_md5;

# Loop through the thread que.
	while ((my $fn = $q->dequeue_nb()) or !$stopping) {
		if (! length($fn)) { yield(); next; }

		$tmp_md5 = md5sum($fn);
		if (! length($tmp_md5)) { next; }

		$md5h{$fn} = $tmp_md5;

		say $tid . ' ' . $fn . ': done indexing (' . $file_stack . ')';

		{ lock($n);
		$n++; }

# If the $saw_sigint variable has been tripped.
# Quit this 'while' loop, thereby closing the thread.
		if ($saw_sigint) {
			say 'Closing thread: ' . $tid;
			iquit();
		}
	}
}

# Subroutine for testing to see if the MD5 sums in the database file are
# correct (i.e. have changed or not).
sub md5test {
	my $tid = threads->tid();
	my ($tmp_md5, $old_md5, $new_md5);

# Loop through the thread queue.
	while ((my $fn = $q->dequeue_nb()) or !$stopping) {
		if (! length($fn)) { yield(); next; }

		$tmp_md5 = md5sum($fn);
		if (! length($tmp_md5)) { next; }

		$new_md5 = $tmp_md5;
		$old_md5 = $md5h{$fn};

		say $tid . ' ' . $fn . ': done testing (' . $file_stack . ')';

# If the new MD5 sum doesn't match the one in the hash, and file doesn't
# already exist in the %err hash, log it and replace the old MD5 sum in
# the hash with the new one.
		if ($new_md5 ne $old_md5 && ! length($err{$fn})) {
			logger('diff', $fn);
			$md5h{$fn} = $new_md5;
		}

		{ lock($n);
		$n++; }

# If the $saw_sigint variable has been tripped.
# Quit this 'while' loop, thereby closing the thread.
		if ($saw_sigint) {
			say 'Closing thread: ' . $tid;
			iquit();
		}
	}
}

# Subroutine for getting the MD5 hash of FLAC files by reading their
# metadata. If the mode is 'test', the FLAC files will also be tested.
# It takes 1 argument:
# (1) file name
sub md5flac {
	my $fn = shift;
	my $hash;

	if (scalar(@flac_req) == 2) {
		chomp($hash = `metaflac --show-md5sum "$fn" 2>&-`);
		if ($? != 0 && $? != 2) { logger('corr', $fn); return; }

		if ($mode eq 'test') {
			open(my $flac_test, '|-', 'flac', '--totally-silent', '--test', '-')
			or die "Can't open 'flac': $!";
			print $flac_test $file_contents{$fn};
			close($flac_test);

			if ($? != 0 && $? != 2) { logger('corr', $fn); return; }
		}

		return $hash;
	}
}

# Subroutine for figuring out which files have gone missing. If
# identical MD5 hashes can be found in %md5h, then delete those keys
# from %gone. When done, loop through the %gone hash and echo each key
# to the logger.
sub p_gone {
# If %gone_tmp is empty, return from this subroutine.
	if (! keys(%gone_tmp)) { return; }

	my %gone;
	my @gone;
	my $size = %gone_tmp;

# Translates the %gone_tmp hash to the %gone hash / array. We need to do
# it in this complicated way because 'threads::shared' has no support
# for hashes within hashes and arrays within arrays. That's why the
# global variables are only simple arrays, and we translate them to a
# hash / array here (in this subroutine).
	foreach my $fn (keys(%gone_tmp)) {
		my $hash = $gone_tmp{${fn}};
		push(@{$gone{${hash}}}, $fn);
	}

# Deletes the %gone_tmp hash as it's not needed anymore.
	{ lock(%gone_tmp);
	undef(%gone_tmp); }

# Loops through the %md5h hash and deletes every matching MD5 hash from
# the %gone hash / array.
	foreach my $fn (keys(%md5h)) {
		my $hash = ${md5h{${fn}}};
		if ($gone{${hash}}) {
			delete($gone{${hash}});
		}
	}

# Translates the %gone hash to @gone array.
# Because then we can sort by filename before printing to the logger.
	foreach my $hash (keys(%gone)) {
		foreach my $fn (@{$gone{${hash}}}) {
			push(@gone, $fn);
		}
	}

# Deletes the %gone hash as it's not needed anymore.
	undef(%gone);

# Logs all missing files.
	foreach my $fn (sort(@gone)) {
		logger('gone', $fn);
	}
}

# Depending on which script mode is active, set the @run array to the
# correct arguments. This will be used to start the threads later.
my @run;
given ($mode) {
	when ('index') {
		@run = (\&md5index);
	}
	when ('test') {
		@run = (\&md5test);
	}
}

# If script mode is either 'import' or 'double' we'll start only one
# thread, else we'll start as many as the available number of CPUs.
my @threads;
if ($mode ne 'import' && $mode ne 'double') {
	foreach (1 .. $cores) {
		push(@threads, threads->create(@run));
	}
}

# This loop is where the actual action takes place (i.e. where all the
# subroutines get called from).
foreach my $dn (@lib) {
	if (-d $dn) {
# Change directory to $dn.
		chdir($dn) or die "Can't change directory to '$dn': $!";

# Start logging.
		logger('start');

# Initialize the database hash, and the files array.
# The init_hash subroutine returns references.
		my($files, $md5dbs) = init_hash($dn);

		if ($mode ne 'import' && $mode ne 'index') {
			if_empty();
		}

		given ($mode) {
			when ('double') {
# Find identical files in database.
				md5double();
			}
			when ('import') {
# For all the files in $dn, run md5import.
				foreach my $fn (@{$files}) { md5import($fn); }

			}
			when ('index') {
				foreach my $fn (@{$files}) {
					if ($saw_sigint) { iquit(); }
					while ($file_stack >= $disk_size) {
						my $active = threads->running();
						say $active . ': ' . $file_stack . ' > ' .
						$disk_size;
						yield();
					}
# Unless file name exists in the database hash, continue.
					if ($md5h{$fn}) { next; }

					if ($fn =~ /.flac$/i) { $q->enqueue($fn); }
					else { file2ram($fn); }
				}
			}
			when ('test') {
# Fetch all the keys for the database hash and put them in the queue.
				foreach my $fn (sort(keys(%md5h))) {
					if ($saw_sigint) { iquit(); }
					while ($file_stack >= $disk_size) {
						say $file_stack . ' > ' . $disk_size;
						yield();
					}

					file2ram($fn);
				}
			}
		}

		if (%large) {
			while ($file_stack > 0) {
				say $file_stack . ' > ' . '0';
				yield();
			}
			foreach my $fn (sort(keys(%large))) {
				$q->enqueue($fn);
			}
		}

		{ lock($stopping);
		$stopping = 1; }

		foreach my $t (threads->list()) { $t->join(); }
# say("All threads joined");

		p_gone();

# Print the hash to the database file and close the log.
		hash2file();
		logger('end', $n);
	}
}
