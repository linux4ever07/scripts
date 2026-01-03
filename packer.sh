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

declare mode session c_tty
declare no_ext ext
declare -A regex input output

session="${RANDOM}-${RANDOM}"
output[stdout_fn]="/dev/shm/packer_stdout-${session}.txt"
c_tty=$(tty)

regex[dev]='^\/dev'
regex[fn]='^(.*)\.([^.]*)$'
regex[tar]='^\.tar\.[^.]*$'
regex[dar]='^\.[[:digit:]]+\.dar$'

# Redirect STDOUT to a file, to capture the output. Only STDERR will be
# displayed, which ensures that errors and prompts will always be
# visible in real-time.
touch "${output[stdout_fn]}"
exec 1>>"${output[stdout_fn]}"

# Creates a function, called 'iquit', which will restore STDOUT to the
# shell, and then quit.
iquit () {
	if [[ $c_tty =~ ${regex[dev]} ]]; then
		exec 1>"$c_tty"
	fi

	rm -f "${output[stdout_fn]}"

	exit
}

# Creates a function, called 'usage', which will print usage
# instructions and then quit.
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

	iquit
}

# Trap signals (INT, TERM) and call iquit.
trap iquit SIGINT SIGTERM

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

# Creates a function, called 'print_stdout', which will print STDOUT.
print_stdout () {
	declare -a lines

	mapfile -t lines <"${output[stdout_fn]}"

	printf '%s\n' "${lines[@]}"

	truncate -s 0 "${output[stdout_fn]}"
}

# Creates a function, called 'output', which will let the user know if
# the command succeeded or not. The output from STDOUT is captured, but
# I see no reason to print it, as all the useful information will
# already have been printed by default, due to STDERR effectively
# replacing STDOUT in this script.
output () {
	declare exit_status
	declare -a stdout_lines

	exit_status="$1"

	mapfile -t stdout_lines < <(print_stdout)

	if [[ $exit_status -eq 0 ]]; then
		printf '\n%s: %s\n' "${input[fn]}" 'Everything is Ok'
	else
		printf '\n%s: %s\n' "${input[fn]}" 'Something went wrong'
	fi
}

# Creates a function, called 'check_cmd', which will be used to check if
# the necessary commands are installed.
check_cmd () {
	declare cmd_tmp name_tmp
	declare -A cmd name

	cmd[dar]='dar'
	cmd[7z]='7za'
	cmd[rar]='rar'
	cmd[cab]='cabextract'
	cmd[arj]='7z'
	cmd[iso]='7z'
	cmd[lzh]='7z'

	name[dar]='dar'
	name[7z]='7zip'
	name[rar]='rar'
	name[cab]='cabextract'
	name[arj]='7zip'
	name[iso]='7zip'
	name[lzh]='7zip'

	cmd_tmp=$(command -v "${cmd[${1}]}")
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
		iquit
	fi
}

# Creates a function, called 'get_ext', which will separate file names
# and extensions.
get_ext () {
	declare -a ext_list

	no_ext="$1"

	while [[ $no_ext =~ ${regex[fn]} ]]; do
		no_ext="${BASH_REMATCH[1]}"
		ext_list=("${BASH_REMATCH[2],,}" "${ext_list[@]}")

		if [[ ${#ext_list[@]} -eq $2 ]]; then
			break
		fi
	done

	ext=$(printf '.%s' "${ext_list[@]}")
}

# Creates a function, called 'set_names', which will create variables
# for file names.
set_names () {
	declare switch

	switch=0

	input[fn]=$(readlink -f "$1")
	input[dn]=$(dirname "${input[fn]}")
	input[bn]=$(basename "${input[fn]}")

	get_ext "${input[bn]}" 2

	if [[ $ext =~ ${regex[tar]} ]]; then
		switch=1
	fi

	if [[ $ext =~ ${regex[dar]} ]]; then
		switch=1
	fi

	if [[ $switch -eq 0 ]]; then
		get_ext "${input[bn]}" 1
	fi

	no_ext="${input[dn]}/${no_ext}"
}

# Creates a function, called 'arch_pack', which will create an archive.
arch_pack () {
	case "$ext" in
		*.tar)
			tar -cf "${no_ext}.tar" "$@"
			output "$?" 1>&2
		;;
		*.tar.gz|*.tgz)
			tar -c "$@" | gzip -9 > "${no_ext}.tar.gz"
			output "$?" 1>&2
		;;
		*.tar.bz2|*.tbz|*.tbz2)
			tar -c "$@" | bzip2 --compress -9 > "${no_ext}.tar.bz2"
			output "$?" 1>&2
		;;
		*.tar.xz|*.txz)
			tar -c "$@" | xz --compress -9 > "${no_ext}.tar.xz"
			output "$?" 1>&2
		;;
		*.zip)
			zip -r -9 "${input[fn]}" "$@"
			output "$?" 1>&2
		;;
		*.7z)
			check_cmd 7z 1>&2

			7za a -t7z -m0=lzma -mx=9 -mfb=64 -md=32m -ms=on "${input[fn]}" "$@"
			output "$?" 1>&2
		;;
		*.rar)
			check_cmd rar 1>&2

			rar a -m5 "${input[fn]}" "$@"
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
	input[bn_iso]="${input[bn]%.*}"
	output[dn_iso_mnt]="/dev/shm/${input[bn_iso]}-${session}"
	output[dn_iso]="${PWD}/${input[bn_iso]}-${session}"

	printf '\n%s: %s\n' "${output[dn_iso]}" 'Creating output directory...'
	mkdir "${output[dn_iso_mnt]}" "${output[dn_iso]}"

	printf '\n%s: %s\n' "${input[fn]}" 'Mounting...'
	sudo mount "${input[fn]}" "${output[dn_iso_mnt]}" -o loop

	printf '\n%s: %s\n' "${input[fn]}" 'Extracting files...'
	cp -rp "${output[dn_iso_mnt]}"/* "${output[dn_iso]}"

	printf '\n%s: %s %s...\n' "${output[dn_iso]}" 'Changing owner to' "$USER"
	sudo chown -R "${USER}:${USER}" "${output[dn_iso]}"
	sudo chmod -R +rw "${output[dn_iso]}"

	printf '\n%s: %s\n' "${input[fn]}" 'Unmounting...'
	sudo umount "${output[dn_iso_mnt]}"

	printf '\n%s: %s\n' "${output[dn_iso_mnt]}" 'Removing mountpoint...'
	rm -rf "${output[dn_iso_mnt]}"
}

# Creates a function, called 'arch_unpack', which will extract an
# archive.
arch_unpack () {
	case "$ext" in
		*.dar)
			check_cmd dar 1>&2

			dar -x "$no_ext"
			output "$?" 1>&2
		;;
		*.tar)
			tar -xf "${input[fn]}"
			output "$?" 1>&2
		;;
		*.tar.z|*.tar.gz|*.tgz)
			tar -xzf "${input[fn]}"
			output "$?" 1>&2
		;;
		*.tar.bz2|*.tbz|*.tbz2)
			tar -xjf "${input[fn]}"
			output "$?" 1>&2
		;;
		*.tar.xz|*.txz)
			tar -xJf "${input[fn]}"
			output "$?" 1>&2
		;;
		*.z|*.gz)
			gunzip "${input[fn]}"
			output "$?" 1>&2
		;;
		*.bz2)
			bunzip2 "${input[fn]}"
			output "$?" 1>&2
		;;
		*.xz)
			unxz "${input[fn]}"
			output "$?" 1>&2
		;;
		*.zip)
			unzip "${input[fn]}"
			output "$?" 1>&2
		;;
		*.7z)
			check_cmd 7z 1>&2

			7za x "${input[fn]}"
			output "$?" 1>&2
		;;
		*.rar)
			check_cmd rar 1>&2

			rar x "${input[fn]}"
			output "$?" 1>&2
		;;
		*.lzh|*.lha)
			check_cmd lzh 1>&2

			7z x "${input[fn]}"
			output "$?" 1>&2
		;;
		*.cab|*.exe)
			check_cmd cab 1>&2

			cabextract "${input[fn]}"
			output "$?" 1>&2
		;;
		*.arj)
			check_cmd arj 1>&2

			7z x "${input[fn]}"
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

# Creates a function, called 'arch_test', which will test an archive.
arch_test () {
	case "$ext" in
		*.dar)
			check_cmd dar 1>&2

			dar -t "$no_ext"
			output "$?" 1>&2
		;;
		*.tar)
			tar -tf "${input[fn]}"
			output "$?" 1>&2
		;;
		*.z|*.gz)
			gunzip -t "${input[fn]}"
			output "$?" 1>&2
		;;
		*.bz2)
			bunzip2 -t "${input[fn]}"
			output "$?" 1>&2
		;;
		*.xz)
			xz -t "${input[fn]}"
			output "$?" 1>&2
		;;
		*.zip)
			unzip -t "${input[fn]}"
			output "$?" 1>&2
		;;
		*.7z)
			check_cmd 7z 1>&2

			7za t "${input[fn]}"
			output "$?" 1>&2
		;;
		*.rar)
			check_cmd rar 1>&2

			rar t "${input[fn]}"
			output "$?" 1>&2
		;;
		*.lzh|*.lha)
			check_cmd lzh 1>&2

			7z t "${input[fn]}"
			output "$?" 1>&2
		;;
		*.cab|*.exe)
			check_cmd cab 1>&2

			cabextract -t "${input[fn]}"
			output "$?" 1>&2
		;;
		*.arj)
			check_cmd arj 1>&2

			7z t "${input[fn]}"
			output "$?" 1>&2
		;;
		*.iso)
			check_cmd iso 1>&2

			7z t "${input[fn]}"
			output "$?" 1>&2
		;;
		*)
			usage 1>&2
		;;
	esac
}

# Creates a function, called 'arch_list', which will list the content of
# an archive.
arch_list () {
	case "$ext" in
		*.dar)
			check_cmd dar 1>&2

			dar -l "$no_ext" | less 1>&2
			output "$?" 1>&2
		;;
		*.tar)
			tar -tvf "${input[fn]}" | less 1>&2
			output "$?" 1>&2
		;;
		*.tar.z|*.tar.gz|*.tgz)
			tar -ztvf "${input[fn]}" | less 1>&2
			output "$?" 1>&2
		;;
		*.tar.bz2|*.tbz|*.tbz2)
			tar -jtvf "${input[fn]}" | less 1>&2
			output "$?" 1>&2
		;;
		*.tar.xz|*.txz)
			tar -Jtvf "${input[fn]}" | less 1>&2
			output "$?" 1>&2
		;;
		*.z|*.gz)
			gunzip -l "${input[fn]}" | less 1>&2
			output "$?" 1>&2
		;;
		*.bz2)
			bunzip2 -t "${input[fn]}" | less 1>&2
			output "$?" 1>&2
		;;
		*.xz)
			unxz -l "${input[fn]}" | less 1>&2
			output "$?" 1>&2
		;;
		*.zip)
			unzip -l "${input[fn]}" | less 1>&2
			output "$?" 1>&2
		;;
		*.7z)
			check_cmd 7z 1>&2

			7za l "${input[fn]}" | less 1>&2
			output "$?" 1>&2
		;;
		*.rar)
			check_cmd rar 1>&2

			rar vb "${input[fn]}" | less 1>&2
			output "$?" 1>&2
		;;
		*.lzh|*.lha)
			check_cmd lzh 1>&2

			7z l "${input[fn]}" | less 1>&2
			output "$?" 1>&2
		;;
		*.cab|*.exe)
			check_cmd cab 1>&2

			cabextract -l "${input[fn]}" | less 1>&2
			output "$?" 1>&2
		;;
		*.arj)
			check_cmd arj 1>&2

			7z l "${input[fn]}" | less 1>&2
			output "$?" 1>&2
		;;
		*.iso)
			check_cmd iso 1>&2

			7z l "${input[fn]}" | less 1>&2
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
		if [[ -f ${input[fn]} ]]; then
			printf '\n%s: %s\n\n' "${input[fn]}" 'File already exists' 1>&2
			iquit
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

			if [[ ! -f ${input[fn]} || ! -r ${input[fn]} ]]; then
				usage 1>&2
			fi

			arch_unpack

			shift
		done
	;;
	'test')
		while [[ $# -gt 0 ]]; do
			set_names "$1"

			if [[ ! -f ${input[fn]} || ! -r ${input[fn]} ]]; then
				usage 1>&2
			fi

			arch_test

			shift
		done
	;;
	'list')
		while [[ $# -gt 0 ]]; do
			set_names "$1"

			if [[ ! -f ${input[fn]} || ! -r ${input[fn]} ]]; then
				usage 1>&2
			fi

			arch_list

			shift
		done
	;;
esac

printf '\n' 1>&2

iquit
