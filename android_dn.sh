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
declare -a targets dirs_in dirs_out
declare -A input output regex

input[dn]=$(readlink -f "$1")
targets=('Android' 'LOST.DIR' 'System Volume Information' '.Trash*')

pause_msg='Are you sure? [y/n]: '

regex[digit]='^[[:digit:]]+$'
regex[size]='^[[:digit:]]+M'
regex[date]='^[[:digit:]]{4}-[[:digit:]]{2}-[[:digit:]]{2}'

# Creates a function, called 'menu'. It displays 2 menus. First it
# displays the directories found, and once a directory is selected it
# displays options ('list' and 'remove').
menu () {
	declare date n size

# Directory menu.
	clear

	printf '\nChoose directory:\n\n'

	for (( i = 0; i < ${#dirs_out[@]}; i++ )); do
		input[tmp_dn]="${dirs_out[${i}]}"
		size=$(du -BM -s "${input[tmp_dn]}" | grep -Eo "${regex[size]}")

		printf '%s) %s (%s)\n' "$i" "${input[tmp_dn]}" "$size"
	done

	printf '\n'
	read -p '>'

	if [[ ! $REPLY =~ ${regex[digit]} ]]; then
		return
	fi

	input[tmp_dn]="${dirs_out[${REPLY}]}"
	n="$REPLY"

	if [[ -z ${input[tmp_dn]} ]]; then
		return
	fi

# Options menu.
	clear

	printf '\n%s\n\n' "${input[tmp_dn]}"
	printf 'Choose action:\n\n'
	printf '(l) list\n'
	printf '(r) remove\n\n'

	read -p '>'

	case "$REPLY" in
		'l')
			declare -a files

			mapfile -t files < <(find "${input[tmp_dn]}" -type f 2>&-)

			for (( i = 0; i < ${#files[@]}; i++ )); do
				input[fn]="${files[${i}]}"
				date=$(stat -c '%y' "${input[fn]}" | grep -Eo "${regex[date]}")

				printf '%s (%s)\n' "${input[fn]}" "$date"
			done | less

			unset -v files
		;;
		'r')
			printf '\n'
			read -p "$pause_msg"

			if [[ $REPLY != 'y' ]]; then
				return
			fi

			unset dirs_out["${n}"]
			dirs_out=("${dirs_out[@]}")

			rm -rf "${input[tmp_dn]}"
		;;
		*)
			return
		;;
	esac
}

# Gets all directories that matches the target names.
for (( i = 0; i < ${#targets[@]}; i++ )); do
	input[tmp_dn]="${targets[${i}]}"

	mapfile -t dirs_in < <(find "${input[dn]}" -type d -iname "${input[tmp_dn]}" 2>&-)
	dirs_out+=("${dirs_in[@]}")
done

unset -v dirs_in

# If no directories were found, quit.
if [[ ${#dirs_out[@]} -eq 0 ]]; then
	printf '\n%s\n\n' 'Nothing to do!'
	exit
fi

# While there's still directories left in the 'dirs_out' array, display
# the menu. If the user wants to quit before that, they can just press
# Ctrl+C.
while [[ ${#dirs_out[@]} -gt 0 ]]; do
	menu
done
