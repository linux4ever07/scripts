#!/bin/bash

# This script is meant to find Android settings, volume information
# directories, and trash directories, list their size and content, and
# give the user the option to remove them.

set -eo pipefail

usage () {
	printf '\n%s\n\n' "Usage: $(basename "$0") [directory]"
	exit
}

if [[ $# -ne 1 || ! -d $1 ]]; then
	usage
fi

declare -a target dirs
in_dn=$(readlink -f "$1")
targets=('Android' 'System Volume Information' '.Trash*')

pause_msg='Are you sure? [y/n]: '

regex_num='^[0-9]+$'
regex_size='^[0-9]+M'
regex_date='^[0-9]{4}\-[0-9]{2}\-[0-9]{2}'

menu_1 () {
	clear

	printf '\nChoose directory:\n\n'

	for (( i = 0; i < ${#dirs[@]}; i++ )); do
		dn="${dirs[${i}]}"
		size=$(du -BM -s "$dn" | grep -Eo "$regex_size")

		printf '%s) %s (%s)\n' "$i" "$dn" "$size"
	done

	printf '\n'
	read -p '>'

	if [[ ! $REPLY =~ $regex_num ]]; then
		return
	fi

	ref_dn="dirs[${REPLY}]"

	if [[ -z ${!ref_dn} ]]; then
		return
	fi

	menu_2 "${!ref_dn}"
}

menu_2 () {
	tmp_dn="$1"

	clear

	printf '\n%s\n\n' "$tmp_dn"
	printf 'Choose action:\n\n'
	printf '(l) list\n'
	printf '(r) remove\n\n'

	read -p '>'

	case "$REPLY" in
		'l')
			mapfile -t files < <(find "$tmp_dn" -type f 2>&-)

			for (( i = 0; i < ${#files[@]}; i++ )); do
				fn="${files[${i}]}"
				date=$(stat -c '%y' "$fn" | grep -Eo "$regex_date")

				printf '%s (%s)\n' "$fn" "$date"
			done | less

			unset -v files
		;;
		'r')
			printf '\n'
			read -p "$pause_msg"

			if [[ $REPLY != 'y' ]]; then
				return
			fi

			for (( i = 0; i < ${#dirs[@]}; i++ )); do
				if [[ ${dirs[${i}]} == "$tmp_dn" ]]; then
					unset dirs["${i}"]
					break
				fi
			done

			dirs=("${dirs[@]}")

			rm -rf "$tmp_dn"
		;;
		*)
			return
		;;
	esac
}

for dn in "${targets[@]}"; do
	mapfile -t dirs_tmp < <(find "$in_dn" -type d -iname "$dn" 2>&-)
	dirs+=("${dirs_tmp[@]}")
done

unset -v dirs_tmp

if [[ ${#dirs[@]} -eq 0 ]]; then
	printf '\n%s\n\n' 'Nothing to do!'
	exit
fi

while [[ ${#dirs[@]} -gt 0 ]]; do
	menu_1
done
