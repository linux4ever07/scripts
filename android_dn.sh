#!/bin/bash

# This script is meant to find Android settings, lost files, volume
# information, and trash directories, list their size and content, and
# give the user the option to remove them.

set -eo pipefail

# Creates a function, called 'usage', which will print usage
# instructions and then quit.
usage () {
	printf '\n%s\n\n' "Usage: $(basename "$0") [directory]"
	exit
}

# If the number of arguments given to the script is not 1, and that
# argument is not a directory, quit.
if [[ $# -ne 1 || ! -d $1 ]]; then
	usage
fi

declare pause_msg
declare -a targets dirs dirs_tmp
declare -A if

if[dn]=$(readlink -f "$1")
targets=('Android' 'LOST.DIR' 'System Volume Information' '.Trash*')

pause_msg='Are you sure? [y/n]: '

declare -A regex

regex[num]='^[0-9]+$'
regex[size]='^[0-9]+M'
regex[date]='^[0-9]{4}-[0-9]{2}-[0-9]{2}'

# Creates a function, called 'menu'. It displays 2 menus. First it
# displays the directories found, and once a directory is selected it
# displays options ('list' and 'remove').
menu () {
	declare date n size

# Directory menu.
	clear

	printf '\nChoose directory:\n\n'

	for (( i = 0; i < ${#dirs[@]}; i++ )); do
		if[dn_tmp]="${dirs[${i}]}"
		size=$(du -BM -s "${if[dn_tmp]}" | grep -Eo "${regex[size]}")

		printf '%s) %s (%s)\n' "$i" "${if[dn_tmp]}" "$size"
	done

	printf '\n'
	read -p '>'

	if [[ ! $REPLY =~ ${regex[num]} ]]; then
		return
	fi

	if[dn_tmp]="${dirs[${REPLY}]}"
	n="$REPLY"

	if [[ -z ${if[dn_tmp]} ]]; then
		return
	fi

# Options menu.
	clear

	printf '\n%s\n\n' "${if[dn_tmp]}"
	printf 'Choose action:\n\n'
	printf '(l) list\n'
	printf '(r) remove\n\n'

	read -p '>'

	case "$REPLY" in
		'l')
			declare -a files

			mapfile -t files < <(find "${if[dn_tmp]}" -type f 2>&-)

			for (( i = 0; i < ${#files[@]}; i++ )); do
				if[fn]="${files[${i}]}"
				date=$(stat -c '%y' "${if[fn]}" | grep -Eo "${regex[date]}")

				printf '%s (%s)\n' "${if[fn]}" "$date"
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

			rm -rf "${if[dn_tmp]}"
		;;
		*)
			return
		;;
	esac
}

# Gets all directories that matches the target names.
for (( i = 0; i < ${#targets[@]}; i++ )); do
	if[dn_tmp]="${targets[${i}]}"

	mapfile -t dirs_tmp < <(find "${if[dn]}" -type d -iname "${if[dn_tmp]}" 2>&-)
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
