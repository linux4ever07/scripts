#!/bin/bash

# This script is a tool for handling archives in various formats.
# The archive format to be used is decided based on the file name
# extension of the archive names given as arguments.

# The benefit of using this script instead of running the compression
# programs directly, is that there's no need to remember the varying
# syntax. And the appropriate program for each specific archive format
# is automatically used.

# The script has these modes:

# * pack
# Compress files / directories to archives. In all cases, the maximum
# compression level is used.

# * unpack
# Extract archives.

# * test
# Test archives.

# * list
# List the content of archives.

# The script lets you know if there were errors or not.

set -o pipefail

declare f f_bn f_bn_lc of
session="${RANDOM}-${RANDOM}"
stdout_f="/dev/shm/packer_stdout-${session}.txt"
c_tty=$(tty)

regex_ext='(\.tar){0,1}(\.[^.]*)$'
regex_dar='(\.[0-9]+){0,1}(\.dar)$'

# Redirect STDOUT to a file, to capture the output. Only STDERR will be
# displayed, which ensures that errors and prompts will always be
# visible in real-time.
touch "$stdout_f"
exec 1>>"$stdout_f"

# trap ctrl-c and call ctrl_c()
trap ctrl_c INT

ctrl_c () {
	printf '%s\n' '** Trapped CTRL-C' 1>&2
	restore_n_quit
}

# Creates a function called 'restore_n_quit', which will restore STDOUT
# to the shell, and then quit.
restore_n_quit () {
	regex_dev='^/dev'

	if [[ $c_tty =~ $regex_dev ]]; then
		exec 1>"$c_tty"
	fi

	rm -f "$stdout_f"
	exit
}

# This function prints usage instructions and then quits.
usage () {
	cat <<USAGE

Usage: $(basename "$0") [mode] [archive] [files...]

Supported archive formats in all modes:

tar, tar.gz|tgz, tar.bz2|tbz|tbz2, tar.xz|txz, zip, 7z, rar

These additional archive formats are supported by the 'unpack', 'test'
and 'list' modes:

dar, z|gz, bz2, xz, lzh|lha, cab|exe, arj, iso


	Mode arguments:

a
	Compress files / directories to archives.

x
	Extract archives.

t
	Test archives.

l
	List the content of archives.

USAGE

	restore_n_quit
}

# If there are no arguments to the script, print usage and then quit.
if [[ $# -lt 2 ]]; then
	usage 1>&2
fi

# The part below sets the mode to be used, based on the first argument
# to the script.
case "$1" in
	'a')
		mode='pack'
	;;
	'x')
		mode='unpack'
	;;
	't')
		mode='test'
	;;
	'l')
		mode='list'
	;;
	*)
		usage 1>&2
	;;
esac

shift

# If no mode was specified through the arguments, print usage and quit.
if [[ -z $mode ]]; then
	usage 1>&2
fi

# Creates a function called 'print_stdout', which will print STDOUT.
print_stdout () {
	while read line; do
		printf '%s\n' "$line"
	done <"$stdout_f"

	truncate -s 0 "$stdout_f"
}

# Creates a function, called 'output', which will let the user know if
# the command succeeded or not. The output from STDOUT is captured, but
# I see no reason to print it, as all the useful information will
# already have been printed by default, due to STDERR effectively
# replacing STDOUT in this script.
output () {
	exit_status="$1"

	mapfile -t stdout_lines < <(print_stdout)

	if [[ $exit_status -eq 0 ]]; then
		printf '\n%s: %s\n' "$f" 'Everything is Ok'
	else
		printf '\n%s: %s\n' "$f" 'Something went wrong'
	fi
}

# Creates a function, called 'check_cmd', which will be used to
# check if the needed commands are installed.
check_cmd () {
	check () {
		command -v "$1"
	}

	declare -A cmd name

	cmd[dar]=$(check 'dar')
	cmd[7z]=$(check '7za')
	cmd[rar]=$(check 'rar')
	cmd[cab]=$(check 'cabextract')
	cmd[arj]=$(check '7z')
	cmd[iso]=$(check '7z')
	cmd[lzh]=$(check '7z')

	name[dar]='dar'
	name[7z]='7zip'
	name[rar]='rar'
	name[cab]='cabextract'
	name[arj]='7zip'
	name[iso]='7zip'
	name[lzh]='7zip'

	for cmd_type in "${!cmd[@]}"; do
		if [[ $1 == "$cmd_type" ]]; then
			if [[ -z ${cmd[${cmd_type}]} ]]; then
				cat <<CMD

'${name[${cmd_type}]}' is not installed!
Install it through your package manager.

In the case of 'rar', you can get the Linux version for free @
https://www.rarlab.com/download.htm

Put the 'rar' executable in ${HOME}/bin, and make sure that this
directory is in your PATH variable.

You can modify your PATH variable by editing ${HOME}/.bashrc, and adding
this line:

PATH="\${HOME}/bin:\${PATH}"

CMD
				restore_n_quit
			fi
		fi
	done
}

# Creates a function called 'create_names', which will create variables
# for file names.
create_names () {
	f=$(readlink -f "$1")
	f_bn=$(basename "$f")
	f_bn_lc="${f_bn,,}"
}

# Creates a function called 'arch_pack', which will create an archive.
arch_pack () {
	case "$f_bn_lc" in
		*.tar)
			tar -cf "${of}.tar" "$@"
			output "$?" 1>&2
		;;
		*.tar.gz|*.tgz)
			tar -c "$@" | gzip -9 > "${of}.tar.gz"
			output "$?" 1>&2
		;;
		*.tar.bz2|*.tbz|*.tbz2)
			tar -c "$@" | bzip2 --compress -9 > "${of}.tar.bz2"
			output "$?" 1>&2
		;;
		*.tar.xz|*.txz)
			tar -c "$@" | xz --compress -9 > "${of}.tar.xz"
			output "$?" 1>&2
		;;
		*.zip)
			zip -r -9 "$f" "$@"
			output "$?" 1>&2
		;;
		*.7z)
			check_cmd 7z 1>&2

			7za a -t7z -m0=lzma -mx=9 -mfb=64 -md=32m -ms=on "$f" "$@"
			output "$?" 1>&2
		;;
		*.rar)
			check_cmd rar 1>&2

			rar a -m5 "$f" "$@"
			output "$?" 1>&2
		;;
		*)
			usage 1>&2
		;;
	esac
}

# Creates a function, called 'iso_unpack', which will be used to mount,
# copy files from, and unmount an ISO file. This in effect means
# extracting the ISO.
iso_unpack () {
	iso_bn="${f_bn%.[^.]*}"
	iso_mnt="/dev/shm/${iso_bn}-${session}"
	iso_of="${PWD}/${iso_bn}-${session}"

	printf '\n%s: %s\n' "$iso_of" 'Creating output directory...'
	mkdir "$iso_mnt" "$iso_of"

	printf '\n%s: %s\n' "$f" 'Mounting...'
	sudo mount "$f" "$iso_mnt" -o loop

	printf '\n%s: %s\n' "$f" 'Extracting files...'
	cp -p -r "$iso_mnt"/* "$iso_of"

	printf '\n%s: %s %s...\n' "$iso_of" 'Changing owner to' "$USER"
	sudo chown -R "${USER}:${USER}" "$iso_of"
	sudo chmod -R +rw "$iso_of"

	printf '\n%s: %s\n' "$f" 'Unmounting...'
	sudo umount "$iso_mnt"

	printf '\n%s: %s\n' "$iso_mnt" 'Removing mountpoint...'
	rm -rf "$iso_mnt"
}

# Creates a function called 'arch_unpack', which will extract an
# archive.
arch_unpack () {
	case "$f_bn_lc" in
		*.dar)
			check_cmd dar 1>&2

			f_tmp=$(sed -E "s/${regex_dar}//" <<<"$f")

			dar -x "$f_tmp"
			output "$?" 1>&2
		;;
		*.tar)
			tar -xf "$f"
			output "$?" 1>&2
		;;
		*.tar.z|*.tar.gz|*.tgz)
			tar -xzf "$f"
			output "$?" 1>&2
		;;
		*.tar.bz2|*.tbz|*.tbz2)
			tar -xjf "$f"
			output "$?" 1>&2
		;;
		*.tar.xz|*.txz)
			tar -xJf "$f"
			output "$?" 1>&2
		;;
		*.z|*.gz)
			gunzip "$f"
			output "$?" 1>&2
		;;
		*.bz2)
			bunzip2 "$f"
			output "$?" 1>&2
		;;
		*.xz)
			unxz "$f"
			output "$?" 1>&2
		;;
		*.zip)
			unzip "$f"
			output "$?" 1>&2
		;;
		*.7z)
			check_cmd 7z 1>&2

			7za x "$f"
			output "$?" 1>&2
		;;
		*.rar)
			check_cmd rar 1>&2

			rar x "$f"
			output "$?" 1>&2
		;;
		*.lzh|*.lha)
			check_cmd lzh 1>&2

			7z x "$f"
			output "$?" 1>&2
		;;
		*.cab|*.exe)
			check_cmd cab 1>&2

			cabextract "$f"
			output "$?" 1>&2
		;;
		*.arj)
			check_cmd arj 1>&2

			7z x "$f"
			output "$?" 1>&2
		;;
		*.iso)
			iso_unpack 1>&2
		;;
		*)
			usage 1>&2
		;;
	esac
}

# Creates a function called 'arch_test', which will test an archive.
arch_test () {
	case "$f_bn_lc" in
		*.dar)
			check_cmd dar 1>&2

			f_tmp=$(sed -E "s/${regex_dar}//" <<<"$f")

			dar -t "$f_tmp"
			output "$?" 1>&2
		;;
		*.tar)
			tar -tf "$f"
			output "$?" 1>&2
		;;
		*.z|*.gz)
			gunzip -t "$f"
			output "$?" 1>&2
		;;
		*.bz2)
			bunzip2 -t "$f"
			output "$?" 1>&2
		;;
		*.xz)
			xz -t "$f"
			output "$?" 1>&2
		;;
		*.zip)
			unzip -t "$f"
			output "$?" 1>&2
		;;
		*.7z)
			check_cmd 7z 1>&2

			7za t "$f"
			output "$?" 1>&2
		;;
		*.rar)
			check_cmd rar 1>&2

			rar t "$f"
			output "$?" 1>&2
		;;
		*.lzh|*.lha)
			check_cmd lzh 1>&2

			7z t "$f"
			output "$?" 1>&2
		;;
		*.cab|*.exe)
			check_cmd cab 1>&2

			cabextract -t "$f"
			output "$?" 1>&2
		;;
		*.arj)
			check_cmd arj 1>&2

			7z t "$f"
			output "$?" 1>&2
		;;
		*.iso)
			check_cmd iso 1>&2

			7z t "$f"
			output "$?" 1>&2
		;;
		*)
			usage 1>&2
		;;
	esac
}

# Creates a function called 'arch_list', which will list the content of
# an archive.
arch_list () {
	case "$f_bn_lc" in
		*.dar)
			check_cmd dar 1>&2

			f_tmp=$(sed -E "s/${regex_dar}//" <<<"$f")

			dar -l "$f_tmp" | less 1>&2
			output "$?" 1>&2
		;;
		*.tar)
			tar -tvf "$f" | less 1>&2
			output "$?" 1>&2
		;;
		*.tar.z|*.tar.gz|*.tgz)
			tar -ztvf "$f" | less 1>&2
			output "$?" 1>&2
		;;
		*.tar.bz2|*.tbz|*.tbz2)
			tar -jtvf "$f" | less 1>&2
			output "$?" 1>&2
		;;
		*.tar.xz|*.txz)
			tar -Jtvf "$f" | less 1>&2
			output "$?" 1>&2
		;;
		*.z|*.gz)
			gunzip -l "$f" | less 1>&2
			output "$?" 1>&2
		;;
		*.bz2)
			bunzip2 -t "$f" | less 1>&2
			output "$?" 1>&2
		;;
		*.xz)
			unxz -l "$f" | less 1>&2
			output "$?" 1>&2
		;;
		*.zip)
			unzip -l "$f" | less 1>&2
			output "$?" 1>&2
		;;
		*.7z)
			check_cmd 7z 1>&2

			7za l "$f" | less 1>&2
			output "$?" 1>&2
		;;
		*.rar)
			check_cmd rar 1>&2

			rar vb "$f" | less 1>&2
			output "$?" 1>&2
		;;
		*.lzh|*.lha)
			check_cmd lzh 1>&2

			7z l "$f" | less 1>&2
			output "$?" 1>&2
		;;
		*.cab|*.exe)
			check_cmd cab 1>&2

			cabextract -l "$f" | less 1>&2
			output "$?" 1>&2
		;;
		*.arj)
			check_cmd arj 1>&2

			7z l "$f" | less 1>&2
			output "$?" 1>&2
		;;
		*.iso)
			check_cmd iso 1>&2

			7z l "$f" | less 1>&2
			output "$?" 1>&2
		;;
		*)
			usage 1>&2
		;;
	esac
}

case "$mode" in
	'pack')
		create_names "$1"
		of=$(sed -E "s/${regex_ext}//" <<<"$f")

		shift

# If the archive file name already exists, quit.
		if [[ -f $f ]]; then
			printf '\n%s: %s\n' "$f" 'File already exists' 1>&2
			restore_n_quit
		fi

# If no files / directories to be compressed were given as arguments,
# quit.
		if [[ -z $1 ]]; then
			usage 1>&2
		fi

		arch_pack "$@"
	;;
	'unpack')
		while [[ $# -gt 0 ]]; do
			create_names "$1"

			if [[ ! -f $f || ! -r $f ]]; then
				usage 1>&2
			fi

			arch_unpack

			shift
		done
	;;
	'test')
		while [[ $# -gt 0 ]]; do
			create_names "$1"

			if [[ ! -f $f || ! -r $f ]]; then
				usage 1>&2
			fi

			arch_test

			shift
		done
	;;
	'list')
		while [[ $# -gt 0 ]]; do
			create_names "$1"

			if [[ ! -f $f || ! -r $f ]]; then
				usage 1>&2
			fi

			arch_list

			shift
		done
	;;
esac

printf '\n' 1>&2

restore_n_quit
