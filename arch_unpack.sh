#!/bin/bash
# This script extracts archives and then lets you know if there were
# errors or not.

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

# If there are no arguments to the script, print usage and then exit.
if [[ ! -f $1 ]]; then
	usage
fi

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

# Creates a function, called 'iso_extract', which will be used to mount,
# copy files from, and unmount an ISO file. This in effect means
# extracting the ISO.
iso_extract () {
	iso_bn="${f_bn%.???}"
	iso_mnt="/dev/shm/${f_bn}-${RANDOM}"
	iso_of="${PWD}/${iso_bn}-${RANDOM}"

	printf '%s\n\n' "${iso_of}: Creating output directory..."
	mkdir "$iso_mnt" "$iso_of"

	printf '%s\n\n' "${f}: Mounting..."
	sudo mount "$f" "$iso_mnt" -o loop

	printf '%s\n\n' "${f}: Extracting files..."
	cp -p -r "$iso_mnt"/* "$iso_of"

	printf '%s\n\n' "${iso_of}: Changing owner to ${USER}..."
	sudo chown -R "${USER}:${USER}" "$iso_of"
	sudo chmod -R +rw "$iso_of"

	printf '%s\n\n' "${f}: Unmounting..."
	sudo umount "$iso_mnt"

	printf '%s\n\n' "${iso_mnt}: Removing mountpoint..."
	rm -rf "$iso_mnt"
}

while [[ $# -gt 0 ]]; do
	f=$(readlink -f "$1")
	f_bn=$(basename "$f")
	f_bn_lc=$(tr '[[:upper:]]' '[[:lower:]]' <<<"$f_bn")

	if [[ ! -f $f || ! -r $f ]]; then
		usage
	fi

	case "$f_bn_lc" in
		*.dar)
			check_cmd dar

			dar_of="${PWD}/${f_bn}"
			dar_of=$(sed -E 's/(\.[0-9]+){0,}\.dar//' <<<"$dar_of")
			dar_of="${dar_of}-${RANDOM}"
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
		*.lzh)
			check_cmd lzh

			mapfile -t stdout_v < <(7z x "$f"; printf '%s\n' "$?")
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
			iso_extract
		;;
	esac

	shift
done

restore
