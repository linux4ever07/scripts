#!/bin/bash
# This script lists the content of archives.

set -o pipefail

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

# Creates a function, called 'usage', which will echo usage instructions
# and then exit.
usage () {
	cat <<USAGE
Usage: $(basename "$0") [archives...]

Supported archive formats are:

dar, tar, tar.bz2|tbz|tbz2|bz2, tar.xz|txz|xz, tar.gz|tgz|gz, lzh, zip, 7z, rar, cab|exe, Z, arj, iso

USAGE

	exit
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
		print_stdout
	else
		printf '%s\n\n' "${f}: Something went wrong"
		print_stdout
	fi
}

# If there are no arguments to the script, print usage and then exit.
if [[ -z $1 ]]; then
	usage
fi

while [[ $# -gt 0 ]]; do
	f=$(readlink -f "$1")
	f_bn=$(basename "$f")
	f_bn_lc="${f_bn,,}"

	if [[ ! -f $f || ! -r $f ]]; then
		usage
	fi

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
		*.lzh)
			check_cmd lzh

			mapfile -t stdout_v < <(7z l "$f"; printf '%s\n' "$?")
			output
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
			check_cmd 7z

			mapfile -t stdout_v < <(7z l "$f"; printf '%s\n' "$?")
			output | less
		;;
	esac

	shift
done

restore
