#!/bin/bash
# This script compresses files / directories to archives (in chosen
# format) and then lets you know if there were errors or not. In all
# cases, the script uses maximum compression level.

set -o pipefail

# Creates a variable ($f) with the archive name, which is supposed to be
# the first argument to the script.
f=$(readlink -f "$1")
f_bn=$(basename "$f")
of=$(sed -E 's/(\.tar){0,1}(\.[^.]*)$//' <<<"$1")
stderr_f="/dev/shm/arch_pack_stderr-${RANDOM}.txt"
c_tty=$(tty)

# trap ctrl-c and call ctrl_c()
trap ctrl_c INT

ctrl_c () {
	restore
	printf '%s\n' '** Trapped CTRL-C'
	exit
}

restore () {
	exec 2>"$c_tty"
	cat_stderr
	rm -f "$stderr_f"
}

cat_stderr () {
	stderr_out=$(cat "$stderr_f")

	truncate -s 0 "$stderr_f"

	if [[ $stderr_out ]]; then
		printf '%s\n' "$stderr_out"
	fi
}

touch "$stderr_f"
exec 2>>"$stderr_f"

# Creates an array ($files) with all the files and directories to be
# compressed.
files=("$@")

# Deletes the first element of the files array, because that's the
# intended name of the archive, and not a file to be compressed.
unset -v files[0]

# This function echoes usage instructions and then exits.
usage () {
	cat <<USAGE
Usage: $(basename "$0") [archive] [files...]

Supported archive formats are:

tar, tar.bz2|tbz|tbz2, tar.xz|txz, tar.gz|tgz, zip, 7z, rar

USAGE

	exit
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

	name[dar]='dar'
	name[7z]='7zip'
	name[rar]='rar'
	name[cab]='cabextract'
	name[arj]='7zip'

	for cmd_type in ${!cmd[@]}; do
		if [[ $1 == $cmd_type ]]; then
			if [[ -z ${cmd[${cmd_type}]} ]]; then
				cat <<CMD

'${name[${cmd_type}]}' is not installed!
Install it through your package manager.

In the case of 'rar', you can get the Linux version for free @ https://www.rarlab.com/download.htm
Put the 'rar' executable in ${HOME}/bin, and make sure that this directory is in your PATH variable.
You can modify your PATH variable by editing ${HOME}/.bashrc, and adding this line:

PATH="\${HOME}/bin:\${PATH}"

CMD
				exit
			fi
		fi
	done
}

# Creates a function, called 'output', which will let the user know if
# the extraction went okay or not. If not, print the entire output from
# the compression program.
output () {
	print_stdout () {
		for (( n = 0; n < ${last}; n++ )); do
			printf '%s\n' "${stdout_v[${n}]}"
		done
		unset -v stdout_v
		cat_stderr
	}

	if [[ ${#stdout_v[@]} -gt 0 ]]; then
		last=$(( ${#stdout_v[@]} - 1 ))
	fi

	if [[ "${stdout_v[${last}]}" == "0" ]]; then
		printf '%s\n\n' "${f}: Everything is Ok"
# print_stdout
	else
		printf '%s\n\n' "${f}: Something went wrong"
		print_stdout
	fi
}

# Creates a function, called 'tar_f', which will output an intermediate
# TAR archive to STDOUT, to be piped into a compression program.
tar_f () {
	tar -c "${files[@]}"
}

# Creates a function, called 'exists', which will check if a file
# already exists, and if so it quits running the script.
exists () {
	if [[ -f $f ]]; then
		printf '%s\n\n' "${f}: File already exists"
		exit
	fi
}

# If there are no arguments to the script, print usage and then exit.
if [[ -z $1 || -z $2 ]]; then
	usage
fi

# If an archive with the same name already exists, quit.
exists

# Depending on the filename extension, create an archive accordingly.
case "$f" in
	*.tar)
		mapfile -t stdout_v < <(tar -cf "${of}.tar" "${files[@]}"; printf '%s\n' "$?")
		output
	;;
	*.tar.gz|*.tgz)
		mapfile -t stdout_v < <(tar_f "$f" | gzip -9 > "${of}.tar.gz"; printf '%s\n' "$?")
		output
	;;
	*.tar.bz2|*.tbz|*.tbz2)
		mapfile -t stdout_v < <(tar_f "$f" | bzip2 --compress -9 > "${of}.tar.bz2"; printf '%s\n' "$?")
		output
	;;
	*.tar.xz|*.txz)
		mapfile -t stdout_v < <(tar_f "$f" | xz --compress -9 > "${of}.tar.xz"; printf '%s\n' "$?")
		output
	;;
	*.zip)
		mapfile -t stdout_v < <(zip -r -9 "$f" "${files[@]}"; printf '%s\n' "$?")
		output
	;;
	*.7z)
		check_cmd 7z

		mapfile -t stdout_v < <(7za a -t7z -m0=lzma -mx=9 -mfb=64 -md=32m -ms=on "$f" "${files[@]}"; printf '%s\n' "$?")
		output
	;;
	*.rar)
		check_cmd rar

		mapfile -t stdout_v < <(rar a -m5 "$f" "${files[@]}"; printf '%s\n' "$?")
		output
	;;
	*)
		usage
	;;
esac

restore
