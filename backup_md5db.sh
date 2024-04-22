#!/bin/bash

# This is just a simple script to backup all my main 'md5.db' files.

set -eo pipefail

# If the script isn't run with sudo / root privileges, then quit.
if [[ $EUID -ne 0 ]]; then
	printf '\n%s\n\n' 'You need to be root to run this script!'
	exit
fi

declare date of dn depth
declare -a dirs depths files files_tmp

date=$(date '+%F')
of="${PWD}/md5db_backup_${date}.tar.xz"

dirs=('/home' '/run/media')
depths=('2' '3')

get_files () {
	find "$1" -mindepth "$2" -maxdepth "$2" -type f -name 'md5.db'
}

for (( i = 0; i < ${#dirs[@]}; i++ )); do
	dn="${dirs[${i}]}"
	depth="${depths[${i}]}"

	mapfile -t files_tmp < <(get_files "$dn" "$depth")

	if [[ ${#files_tmp[@]} -eq 0 ]]; then
		continue
	fi

	files+=("${files_tmp[@]}")
done

if [[ ${#files[@]} -eq 0 ]]; then
	exit
fi

tar -c "${files[@]}" | xz --compress -9 > "$of"
