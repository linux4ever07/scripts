#!/bin/bash

# This script is a tool for handling archives in various formats.
# The archive format to be used is decided based on the file name
# extension of the archive names given as arguments.

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
stderr_f="/dev/shm/packer_stderr-${session}.txt"
c_tty=$(tty)

regex_ext='(\.tar){0,1}(\.[^.]*)$'
regex_dar='(\.[0-9]+){0,1}(\.dar)$'

# This function prints usage instructions and then exits.
usage () {
	cat <<USAGE
Usage: $(basename "$0") [mode] [archive] [files...]

Supported archive formats in all modes:

tar, tar.bz2|tbz|tbz2, tar.xz|txz, tar.gz|tgz, zip, 7z, rar

These additional archive formats are supported by the 'unpack', 'test'
and 'list' modes:

dar, bz2, xz, gz, lzh, cab|exe, Z, arj, iso


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

	exit
}

# Creates a function called 'create_names', which will create variables
# for file names.
create_names () {
	f=$(readlink -f "$1")
	f_bn=$(basename "$f")
	f_bn_lc="${f_bn,,}"
}

# If there are no arguments to the script, print usage and then exit.
if [[ -z $1 || -z $2 ]]; then
	usage
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
		usage
	;;
esac

shift

# If no mode was specified through the arguments, print usage and exit.
if [[ -z $mode ]]; then
	usage
fi

# If in 'pack' mode, create variables with the archive name, which is
# supposed to be the second argument to the script.
if [[ $mode == 'pack' ]]; then
	create_names "$1"
	of=$(sed -E "s/${regex_ext}//" <<<"$f")

	shift

# If the archive file name already exists, quit.
	if [[ -f $f ]]; then
		printf '%s: File already exists\n\n' "$f"
		exit
	fi

# If no files / directories to be compressed were given as arguments,
# quit.
	if [[ -z $1 ]]; then
		usage
	fi
fi

# Redirect STDERR to a file, to capture the output.
touch "$stderr_f"
exec 2>>"$stderr_f"

# trap ctrl-c and call ctrl_c()
trap ctrl_c INT

ctrl_c () {
	restore
	printf '%s\n' '** Trapped CTRL-C'
	exit
}

# Creates a function called 'restore', which will restore STDERR to the
# shell.
restore () {
	regex_dev='^/dev'

	if [[ $c_tty =~ $regex_dev ]]; then
		exec 2>"$c_tty"
	fi

	cat_stderr
	rm -f "$stderr_f"
}

# Creates a function called 'cat_stderr', which will print errors, if
# there were any.
cat_stderr () {
	stderr_out=$(cat "$stderr_f")

	truncate -s 0 "$stderr_f"

	if [[ -n $stderr_out ]]; then
		printf '%s\n' "$stderr_out"
	fi
}

# Creates a function, called 'check_cmd', which will be used to
# check if the needed commands are installed.
check_cmd () {
	check() {
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
		if [[ "$1" == "$cmd_type" ]]; then
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
				exit
			fi
		fi
	done
}

# Creates a function, called 'output', which will let the user know if
# the command succeeded or not. If not, print the entire output from
# the compression program.
output () {
	print_stdout () {
		for (( n = 0; n < last; n++ )); do
			printf '%s\n' "${stdout_v[${n}]}"
		done
		unset -v stdout_v
		cat_stderr
	}

	if [[ ${#stdout_v[@]} -gt 0 ]]; then
		last=$(( ${#stdout_v[@]} - 1 ))
	fi

	if [[ "${stdout_v[${last}]}" == "0" ]]; then
		printf '%s: Everything is Ok\n\n' "$f"

		if [[ $mode == 'list' ]]; then
			print_stdout
		fi
	else
		printf '%s: Something went wrong\n\n' "$f"
		print_stdout
	fi
}

# Creates a function called 'arch_pack', which will create an archive.
arch_pack () {
	case "$f_bn_lc" in
		*.tar)
			mapfile -t stdout_v < <(tar -cf "${of}.tar" "${@}"; printf '%s\n' "$?")
			output
		;;
		*.tar.gz|*.tgz)
			mapfile -t stdout_v < <(tar -c "${@}" | gzip -9 > "${of}.tar.gz"; printf '%s\n' "$?")
			output
		;;
		*.tar.bz2|*.tbz|*.tbz2)
			mapfile -t stdout_v < <(tar -c "${@}" | bzip2 --compress -9 > "${of}.tar.bz2"; printf '%s\n' "$?")
			output
		;;
		*.tar.xz|*.txz)
			mapfile -t stdout_v < <(tar -c "${@}" | xz --compress -9 > "${of}.tar.xz"; printf '%s\n' "$?")
			output
		;;
		*.zip)
			mapfile -t stdout_v < <(zip -r -9 "$f" "${@}"; printf '%s\n' "$?")
			output
		;;
		*.7z)
			check_cmd 7z

			mapfile -t stdout_v < <(7za a -t7z -m0=lzma -mx=9 -mfb=64 -md=32m -ms=on "$f" "${@}"; printf '%s\n' "$?")
			output
		;;
		*.rar)
			check_cmd rar

			mapfile -t stdout_v < <(rar a -m5 "$f" "${@}"; printf '%s\n' "$?")
			output
		;;
		*)
			usage
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

	printf '%s: Creating output directory...\n\n' "$iso_of"
	mkdir "$iso_mnt" "$iso_of"

	printf '%s: Mounting...\n\n' "$f"
	sudo mount "$f" "$iso_mnt" -o loop

	printf '%s: Extracting files...\n\n' "$f"
	cp -p -r "$iso_mnt"/* "$iso_of"

	printf '%s: Changing owner to %s...\n\n' "$iso_of" "$USER"
	sudo chown -R "${USER}:${USER}" "$iso_of"
	sudo chmod -R +rw "$iso_of"

	printf '%s: Unmounting...\n\n' "$f"
	sudo umount "$iso_mnt"

	printf '%s: Removing mountpoint...\n\n' "$iso_mnt"
	rm -rf "$iso_mnt"
}

# Creates a function called 'arch_unpack', which will extract an
# archive.
arch_unpack () {
	case "$f_bn_lc" in
		*.dar)
			check_cmd dar

			dar_of=$(sed -E "s/${regex_dar}//" <<<"$f_bn")
			dar_of="${PWD}/${dar_of}-${session}"
			mkdir "$dar_of"

			dar -x "$f" -R "$dar_of"
			cat_stderr
		;;
		*.tar)
			mapfile -t stdout_v < <(tar -xf "$f"; printf '%s\n' "$?")
			output
		;;
		*.tar.z|*.tar.gz|*.tgz)
			mapfile -t stdout_v < <(tar -xzf "$f"; printf '%s\n' "$?")
			output
		;;
		*.tar.bz2|*.tbz|*.tbz2)
			mapfile -t stdout_v < <(tar -xjf "$f"; printf '%s\n' "$?")
			output
		;;
		*.tar.xz|*.txz)
			mapfile -t stdout_v < <(tar -xJf "$f"; printf '%s\n' "$?")
			output
		;;
		*.z|*.gz)
			mapfile -t stdout_v < <(gunzip "$f"; printf '%s\n' "$?")
			output
		;;
		*.bz2)
			mapfile -t stdout_v < <(bunzip2 "$f"; printf '%s\n' "$?")
			output
		;;
		*.xz)
			mapfile -t stdout_v < <(unxz "$f"; printf '%s\n' "$?")
			output
		;;
		*.zip)
			mapfile -t stdout_v < <(unzip "$f"; printf '%s\n' "$?")
			output
		;;
		*.7z)
			check_cmd 7z

			mapfile -t stdout_v < <(7za x "$f"; printf '%s\n' "$?")
			output
		;;
		*.rar)
			check_cmd rar

			mapfile -t stdout_v < <(rar x "$f"; printf '%s\n' "$?")
			output
		;;
		*.lzh)
			check_cmd lzh

			mapfile -t stdout_v < <(7z x "$f"; printf '%s\n' "$?")
			output
		;;
		*.cab|*.exe)
			check_cmd cab

			mapfile -t stdout_v < <(cabextract "$f"; printf '%s\n' "$?")
			output
		;;
		*.arj)
			check_cmd arj

			mapfile -t stdout_v < <(7z x "$f"; printf '%s\n' "$?")
			output
		;;
		*.iso)
			iso_unpack
		;;
		*)
			usage
		;;
	esac
}

# Creates a function called 'arch_test', which will test an archive.
arch_test () {
	case "$f_bn_lc" in
		*.dar)
			check_cmd dar

			dar -t "$f"
			cat_stderr
		;;
		*.tar)
			mapfile -t stdout_v < <(tar tf "$f"; printf '%s\n' "$?")
			output "$f"
		;;
		*.z|*.gz)
			mapfile -t stdout_v < <(gunzip -t "$f"; printf '%s\n' "$?")
			output "$f"
		;;
		*.bz2)
			mapfile -t stdout_v < <(bunzip2 -t "$f"; printf '%s\n' "$?")
			output "$f"
		;;
		*.xz)
			mapfile -t stdout_v < <(xz -t "$f"; printf '%s\n' "$?")
			output "$f"
		;;
		*.zip)
			mapfile -t stdout_v < <(unzip -t "$f"; printf '%s\n' "$?")
			output "$f"
		;;
		*.7z)
			check_cmd 7z

			mapfile -t stdout_v < <(7za t "$f"; printf '%s\n' "$?")
			output "$f"
		;;
		*.rar)
			check_cmd rar

			mapfile -t stdout_v < <(rar t "$f"; printf '%s\n' "$?")
			output "$f"
		;;
		*.lzh)
			check_cmd lzh

			mapfile -t stdout_v < <(7z t "$f"; printf '%s\n' "$?")
			output
		;;
		*.cab|*.exe)
			check_cmd cab

			mapfile -t stdout_v < <(cabextract -t "$f"; printf '%s\n' "$?")
			output "$f"
		;;
		*.arj)
			check_cmd arj

			mapfile -t stdout_v < <(7z t "$f"; printf '%s\n' "$?")
			output "$f"
		;;
		*.iso)
			check_cmd iso

			mapfile -t stdout_v < <(7z t "$f"; printf '%s\n' "$?")
			output "$f"
		;;
		*)
			usage
		;;
	esac
}

# Creates a function called 'arch_list', which will list the content of
# an archive.
arch_list () {
	case "$f_bn_lc" in
		*.dar)
			check_cmd dar

			dar -l "$f" 2>&1 | less
			cat_stderr
		;;
		*.tar)
			mapfile -t stdout_v < <(tar -tvf "$f"; printf '%s\n' "$?")
			output | less
		;;
		*.tar.z|*.tar.gz|*.tgz)
			mapfile -t stdout_v < <(tar -ztvf "$f"; printf '%s\n' "$?")
			output | less
		;;
		*.tar.bz2|*.tbz|*.tbz2)
			mapfile -t stdout_v < <(tar -jtvf "$f"; printf '%s\n' "$?")
			output | less
		;;
		*.tar.xz|*.txz)
			mapfile -t stdout_v < <(tar -Jtvf "$f"; printf '%s\n' "$?")
			output | less
		;;
		*.z|*.gz)
			mapfile -t stdout_v < <(gunzip -l "$f"; printf '%s\n' "$?")
			output | less
		;;
		*.bz2)
			mapfile -t stdout_v < <(bunzip2 -t "$f"; printf '%s\n' "$?")
			output | less
		;;
		*.xz)
			mapfile -t stdout_v < <(unxz -l "$f"; printf '%s\n' "$?")
			output | less
		;;
		*.zip)
			mapfile -t stdout_v < <(unzip -l "$f"; printf '%s\n' "$?")
			output | less
		;;
		*.7z)
			check_cmd 7z

			mapfile -t stdout_v < <(7za l "$f"; printf '%s\n' "$?")
			output | less
		;;
		*.rar)
			check_cmd rar

			mapfile -t stdout_v < <(rar vb "$f"; printf '%s\n' "$?")
			output | less
		;;
		*.lzh)
			check_cmd lzh

			mapfile -t stdout_v < <(7z l "$f"; printf '%s\n' "$?")
			output
		;;
		*.cab|*.exe)
			check_cmd cab

			mapfile -t stdout_v < <(cabextract -l "$f"; printf '%s\n' "$?")
			output | less
		;;
		*.arj)
			check_cmd arj

			mapfile -t stdout_v < <(7z l "$f"; printf '%s\n' "$?")
			output | less
		;;
		*.iso)
			check_cmd iso

			mapfile -t stdout_v < <(7z l "$f"; printf '%s\n' "$?")
			output | less
		;;
		*)
			usage
		;;
	esac
}

case "$mode" in
	'pack')
		arch_pack "${@}"
	;;
	'unpack')
		while [[ $# -gt 0 ]]; do
			create_names "$1"

			if [[ ! -f $f || ! -r $f ]]; then
				usage
			fi

			arch_unpack

			shift
		done
	;;
	'test')
		while [[ $# -gt 0 ]]; do
			create_names "$1"

			if [[ ! -f $f || ! -r $f ]]; then
				usage
			fi

			arch_test

			shift
		done
	;;
	'list')
		while [[ $# -gt 0 ]]; do
			create_names "$1"

			if [[ ! -f $f || ! -r $f ]]; then
				usage
			fi

			arch_list

			shift
		done
	;;
esac

restore
