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

declare if if_bn if_bn_lc of
session="${RANDOM}-${RANDOM}"
stdout_fn="/dev/shm/packer_stdout-${session}.txt"
c_tty=$(tty)

declare -A regex

regex[dev]='^\/dev'
regex[ext]='(\.tar){0,1}(\.[^.]*)$'
regex[dar]='(\.[0-9]+){0,1}(\.dar)$'

# Redirect STDOUT to a file, to capture the output. Only STDERR will be
# displayed, which ensures that errors and prompts will always be
# visible in real-time.
touch "$stdout_fn"
exec 1>>"$stdout_fn"

# trap ctrl-c and call ctrl_c()
trap ctrl_c INT

ctrl_c () {
	printf '%s\n' '** Trapped CTRL-C' 1>&2
	restore_n_quit
}

# Creates a function called 'restore_n_quit', which will restore STDOUT
# to the shell, and then quit.
restore_n_quit () {
	if [[ $c_tty =~ ${regex[dev]} ]]; then
		exec 1>"$c_tty"
	fi

	rm -f "$stdout_fn"
	exit
}

# Creates a function called 'usage', which will print usage instructions
# and then quit.
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
	mapfile -t lines <"$stdout_fn"

	printf '%s\n' "${lines[@]}"

	truncate -s 0 "$stdout_fn"
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
		printf '\n%s: %s\n' "$if" 'Everything is Ok'
	else
		printf '\n%s: %s\n' "$if" 'Something went wrong'
	fi
}

# Creates a function, called 'check_cmd', which will be used to
# check if the needed commands are installed.
check_cmd () {
	check () {
		command -v "$1"
	}

	declare cmd_tmp name_tmp
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

	cmd_tmp="${cmd[${1}]}"
	name_tmp="${name[${1}]}"

	if [[ -z ${cmd_tmp} ]]; then
		cat <<CMD

'${name_tmp}' is not installed!
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
}

# Creates a function called 'set_names', which will create variables for
# file names.
set_names () {
	if=$(readlink -f "$1")
	if_bn=$(basename "$if")
	if_bn_lc="${if_bn,,}"

	of=$(sed -E "s/${regex[ext]}//" <<<"$if")
}

# Creates a function called 'arch_pack', which will create an archive.
arch_pack () {
	case "$if_bn_lc" in
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
			zip -r -9 "$if" "$@"
			output "$?" 1>&2
		;;
		*.7z)
			check_cmd 7z 1>&2

			7za a -t7z -m0=lzma -mx=9 -mfb=64 -md=32m -ms=on "$if" "$@"
			output "$?" 1>&2
		;;
		*.rar)
			check_cmd rar 1>&2

			rar a -m5 "$if" "$@"
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
	iso_bn="${if_bn%.*}"
	iso_mnt="/dev/shm/${iso_bn}-${session}"
	iso_of="${PWD}/${iso_bn}-${session}"

	printf '\n%s: %s\n' "$iso_of" 'Creating output directory...'
	mkdir "$iso_mnt" "$iso_of"

	printf '\n%s: %s\n' "$if" 'Mounting...'
	sudo mount "$if" "$iso_mnt" -o loop

	printf '\n%s: %s\n' "$if" 'Extracting files...'
	cp -rp "$iso_mnt"/* "$iso_of"

	printf '\n%s: %s %s...\n' "$iso_of" 'Changing owner to' "$USER"
	sudo chown -R "${USER}:${USER}" "$iso_of"
	sudo chmod -R +rw "$iso_of"

	printf '\n%s: %s\n' "$if" 'Unmounting...'
	sudo umount "$iso_mnt"

	printf '\n%s: %s\n' "$iso_mnt" 'Removing mountpoint...'
	rm -rf "$iso_mnt"
}

# Creates a function called 'arch_unpack', which will extract an
# archive.
arch_unpack () {
	case "$if_bn_lc" in
		*.dar)
			check_cmd dar 1>&2

			if_tmp=$(sed -E "s/${regex[dar]}//" <<<"$if")

			dar -x "$if_tmp"
			output "$?" 1>&2
		;;
		*.tar)
			tar -xf "$if"
			output "$?" 1>&2
		;;
		*.tar.z|*.tar.gz|*.tgz)
			tar -xzf "$if"
			output "$?" 1>&2
		;;
		*.tar.bz2|*.tbz|*.tbz2)
			tar -xjf "$if"
			output "$?" 1>&2
		;;
		*.tar.xz|*.txz)
			tar -xJf "$if"
			output "$?" 1>&2
		;;
		*.z|*.gz)
			gunzip "$if"
			output "$?" 1>&2
		;;
		*.bz2)
			bunzip2 "$if"
			output "$?" 1>&2
		;;
		*.xz)
			unxz "$if"
			output "$?" 1>&2
		;;
		*.zip)
			unzip "$if"
			output "$?" 1>&2
		;;
		*.7z)
			check_cmd 7z 1>&2

			7za x "$if"
			output "$?" 1>&2
		;;
		*.rar)
			check_cmd rar 1>&2

			rar x "$if"
			output "$?" 1>&2
		;;
		*.lzh|*.lha)
			check_cmd lzh 1>&2

			7z x "$if"
			output "$?" 1>&2
		;;
		*.cab|*.exe)
			check_cmd cab 1>&2

			cabextract "$if"
			output "$?" 1>&2
		;;
		*.arj)
			check_cmd arj 1>&2

			7z x "$if"
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
	case "$if_bn_lc" in
		*.dar)
			check_cmd dar 1>&2

			if_tmp=$(sed -E "s/${regex[dar]}//" <<<"$if")

			dar -t "$if_tmp"
			output "$?" 1>&2
		;;
		*.tar)
			tar -tf "$if"
			output "$?" 1>&2
		;;
		*.z|*.gz)
			gunzip -t "$if"
			output "$?" 1>&2
		;;
		*.bz2)
			bunzip2 -t "$if"
			output "$?" 1>&2
		;;
		*.xz)
			xz -t "$if"
			output "$?" 1>&2
		;;
		*.zip)
			unzip -t "$if"
			output "$?" 1>&2
		;;
		*.7z)
			check_cmd 7z 1>&2

			7za t "$if"
			output "$?" 1>&2
		;;
		*.rar)
			check_cmd rar 1>&2

			rar t "$if"
			output "$?" 1>&2
		;;
		*.lzh|*.lha)
			check_cmd lzh 1>&2

			7z t "$if"
			output "$?" 1>&2
		;;
		*.cab|*.exe)
			check_cmd cab 1>&2

			cabextract -t "$if"
			output "$?" 1>&2
		;;
		*.arj)
			check_cmd arj 1>&2

			7z t "$if"
			output "$?" 1>&2
		;;
		*.iso)
			check_cmd iso 1>&2

			7z t "$if"
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
	case "$if_bn_lc" in
		*.dar)
			check_cmd dar 1>&2

			if_tmp=$(sed -E "s/${regex[dar]}//" <<<"$if")

			dar -l "$if_tmp" | less 1>&2
			output "$?" 1>&2
		;;
		*.tar)
			tar -tvf "$if" | less 1>&2
			output "$?" 1>&2
		;;
		*.tar.z|*.tar.gz|*.tgz)
			tar -ztvf "$if" | less 1>&2
			output "$?" 1>&2
		;;
		*.tar.bz2|*.tbz|*.tbz2)
			tar -jtvf "$if" | less 1>&2
			output "$?" 1>&2
		;;
		*.tar.xz|*.txz)
			tar -Jtvf "$if" | less 1>&2
			output "$?" 1>&2
		;;
		*.z|*.gz)
			gunzip -l "$if" | less 1>&2
			output "$?" 1>&2
		;;
		*.bz2)
			bunzip2 -t "$if" | less 1>&2
			output "$?" 1>&2
		;;
		*.xz)
			unxz -l "$if" | less 1>&2
			output "$?" 1>&2
		;;
		*.zip)
			unzip -l "$if" | less 1>&2
			output "$?" 1>&2
		;;
		*.7z)
			check_cmd 7z 1>&2

			7za l "$if" | less 1>&2
			output "$?" 1>&2
		;;
		*.rar)
			check_cmd rar 1>&2

			rar vb "$if" | less 1>&2
			output "$?" 1>&2
		;;
		*.lzh|*.lha)
			check_cmd lzh 1>&2

			7z l "$if" | less 1>&2
			output "$?" 1>&2
		;;
		*.cab|*.exe)
			check_cmd cab 1>&2

			cabextract -l "$if" | less 1>&2
			output "$?" 1>&2
		;;
		*.arj)
			check_cmd arj 1>&2

			7z l "$if" | less 1>&2
			output "$?" 1>&2
		;;
		*.iso)
			check_cmd iso 1>&2

			7z l "$if" | less 1>&2
			output "$?" 1>&2
		;;
		*)
			usage 1>&2
		;;
	esac
}

case "$mode" in
	'pack')
		set_names "$1"

		shift

# If the archive file name already exists, quit.
		if [[ -f $if ]]; then
			printf '\n%s: %s\n\n' "$if" 'File already exists' 1>&2
			restore_n_quit
		fi

# If no files / directories to be compressed were given as arguments,
# quit.
		if [[ $# -eq 0 ]]; then
			usage 1>&2
		fi

		arch_pack "$@"
	;;
	'unpack')
		while [[ $# -gt 0 ]]; do
			set_names "$1"

			if [[ ! -f $if || ! -r $if ]]; then
				usage 1>&2
			fi

			arch_unpack

			shift
		done
	;;
	'test')
		while [[ $# -gt 0 ]]; do
			set_names "$1"

			if [[ ! -f $if || ! -r $if ]]; then
				usage 1>&2
			fi

			arch_test

			shift
		done
	;;
	'list')
		while [[ $# -gt 0 ]]; do
			set_names "$1"

			if [[ ! -f $if || ! -r $if ]]; then
				usage 1>&2
			fi

			arch_list

			shift
		done
	;;
esac

printf '\n' 1>&2

restore_n_quit
