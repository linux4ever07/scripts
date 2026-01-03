#!/bin/bash

# This is just a simple script to backup all my main 'md5.db' files.

set -eo pipefail

# If the script isn't run with sudo / root privileges, then quit.
if [[ $EUID -ne 0 ]]; then
	printf '\n%s\n\n' 'You need to be root to run this script!'
	exit
fi

declare date depth
declare -a dirs depths files_in files_out
declare -A input output

date=$(date '+%F')
output[fn]="${PWD}/md5db_backup_${date}.tar.xz"

dirs=('/home' '/run/media')
depths=('2' '3')

get_files () {
	find "$1" -mindepth "$2" -maxdepth "$2" -type f -name 'md5.db'
}

for (( i = 0; i < ${#dirs[@]}; i++ )); do
	input[dn]="${dirs[${i}]}"

	depth="${depths[${i}]}"

	mapfile -t files_in < <(get_files "${input[dn]}" "$depth")

	if [[ ${#files_in[@]} -eq 0 ]]; then
		continue
	fi

	files_out+=("${files_in[@]}")
done

if [[ ${#files_out[@]} -eq 0 ]]; then
	exit
fi

tar -c "${files_out[@]}" | xz --compress -9 > "${output[fn]}"
