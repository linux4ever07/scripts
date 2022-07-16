#!/bin/bash
# This script tests archive files passed to it as arguments.

stderr_f="/dev/shm/arch_test_stderr-${RANDOM}.txt"
c_tty=$(tty)

# trap ctrl-c and call ctrl_c()
trap ctrl_c INT

ctrl_c () {
	restore
	echo '** Trapped CTRL-C'
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
		echo "$stderr_out"
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
			echo "${stdout_v[${n}]}"
		done
		unset -v stdout_v
		cat_stderr
	}

	if [[ ${#stdout_v[@]} -gt 0 ]]; then
		last=$(( ${#stdout_v[@]} - 1 ))
	fi

	if [[ "${stdout_v[${last}]}" == "0" ]]; then
		echo -e "${f}: Everything is Ok\n"
# print_stdout
	else
		echo -e "${f}: Something went wrong\n"
		print_stdout
	fi
}

while [[ $# -gt 0 ]]; do
# If there are no arguments to the script, print usage and then exit.
	if [[ ! -f $1 ]]; then
		usage
	fi

	f=$(readlink -f "$1")
	f_bn=$(basename "$f")
	f_lc=$(tr '[[:upper:]]' '[[:lower:]]' <<<"$f_bn")

	if [[ -f $f ]]; then
		case "$f_lc" in
			*.dar)
				check_cmd dar

				dar -t "$f"
				cat_stderr
			;;
			*.tar)
				mapfile -t stdout_v < <(tar tf "$f"; echo "$?")
				output "$f"
			;;
			*.zip)
				mapfile -t stdout_v < <(unzip -t "$f"; echo "$?")
				output "$f"
			;;
			*.z|*.gz)
				mapfile -t stdout_v < <(gunzip -t "$f"; echo "$?")
				output "$f"
			;;
			*.lzh)
				check_cmd lzh

				mapfile -t stdout_v < <(7z t "$f"; echo "$?")
				output
			;;
			*.bz2)
				mapfile -t stdout_v < <(bunzip2 -t "$f"; echo "$?")
				output "$f"
			;;
			*.xz)
				mapfile -t stdout_v < <(xz -t "$f"; echo "$?")
				output "$f"
			;;
			*.7z)
				check_cmd 7z

				mapfile -t stdout_v < <(7za t "$f"; echo "$?")
				output "$f"
			;;
			*.rar|*.part00.rar)
				check_cmd rar

				mapfile -t stdout_v < <(rar t "$f"; echo "$?")
				output "$f"
			;;
			*.cab|*.exe)
				check_cmd cab

				mapfile -t stdout_v < <(cabextract -t "$f"; echo "$?")
				output "$f"
			;;
			*.arj)
				check_cmd arj

				mapfile -t stdout_v < <(7z t "$f"; echo "$?")
				output "$f"
			;;
			*.iso)
				check_cmd iso

				mapfile -t stdout_v < <(7z t "$f"; echo "$?")
				output "$f"
			;;
			esac
	fi

	shift
done

restore

