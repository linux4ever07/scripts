#!/bin/bash

# This script is meant to find Android settings, lost files, volume
# information, and trash directories, list their size and content, and
# give the user the option to remove them.

set -eo pipefail

# Creates a function called 'usage', which prints usage and then quits.
usage () {
	printf '\n%s\n\n' "Usage: $(basename "$0") [directory]"
	exit
}

# If the number of arguments given to the script is not 1, and that
# argument is not a directory, quit.
if [[ $# -ne 1 || ! -d $1 ]]; then
	usage
fi

declare -a targets dirs
in_dn=$(readlink -f "$1")
targets=('Android' 'LOST.DIR' 'System Volume Information' '.Trash*')

pause_msg='Are you sure? [y/n]: '

declare -A regex

regex[num]='^[0-9]+$'
regex[size]='^[0-9]+M'
regex[date]='^[0-9]{4}\-[0-9]{2}\-[0-9]{2}'

# Creates a function called 'menu'. It displays 2 menus. First it
# displays the directories found, and once a directory is selected it
# displays options ('list' and 'remove').
menu () {
# Directory menu.
	clear

	printf '\nChoose directory:\n\n'

	for (( i = 0; i < ${#dirs[@]}; i++ )); do
		dn="${dirs[${i}]}"
		size=$(du -BM -s "$dn" | grep -Eo "${regex[size]}")

		printf '%s) %s (%s)\n' "$i" "$dn" "$size"
	done

	printf '\n'
	read -p '>'

	if [[ ! $REPLY =~ ${regex[num]} ]]; then
		return
	fi

	tmp_dn="${dirs[${REPLY}]}"
	n="$REPLY"

	if [[ -z $tmp_dn ]]; then
		return
	fi

# Options menu.
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
				date=$(stat -c '%y' "$fn" | grep -Eo "${regex[date]}")

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

			unset dirs["${n}"]
			dirs=("${dirs[@]}")

			rm -rf "$tmp_dn"
		;;
		*)
			return
		;;
	esac
}

# Gets all directories that matches the target names.
for dn in "${targets[@]}"; do
	mapfile -t dirs_tmp < <(find "$in_dn" -type d -iname "$dn" 2>&-)
	dirs+=("${dirs_tmp[@]}")
done

unset -v dirs_tmp

# If no directories were found, quit.
if [[ ${#dirs[@]} -eq 0 ]]; then
	printf '\n%s\n\n' 'Nothing to do!'
	exit
fi

# While there's still directories left in the 'dirs' array, display the
# menu. If the user wants to quit before that, they can just press
# Ctrl+C.
while [[ ${#dirs[@]} -gt 0 ]]; do
	menu
done
