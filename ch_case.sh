#!/bin/bash

# This script will recursively change the file / directory names under
# the directory specified to either upper or lower case.

# The use case for this may be for example to change MS-DOS file names
# (for programs and games) to whatever format you prefer, upper case or
# lower case. I'm a *nix user, so I prefer lower case. Since MS-DOS is
# case insensitive it doesn't matter which format you use, as it will
# show up as upper case from within DOS anyway.

set -o pipefail

# Creates a function, called 'usage', which will print usage
# instructions and then quit.
usage () {
	printf '\n%s\n\n' "Usage: $(basename "$0") [dir] [upper|lower]"
	exit
}

if [[ ! -d $1 ]]; then
	usage
elif [[ $2 != 'upper' && $2 != 'lower' ]]; then
	usage
fi

declare case pause_msg
declare -a vars files path_parts
declare -A if of depth

vars=('files' 'path_parts')

if[dn]=$(readlink -f "$1")

case="$2"

depth[max]=0

pause_msg="
You're about to recursively change all the file / directory names
under \"${if[dn]}\" to ${case} case.

Are you sure? [y/n]: "

read -p "$pause_msg"

if [[ $REPLY != 'y' ]]; then
	exit
fi

printf '\n'

mapfile -d'/' -t path_parts <<<"${if[dn]}"
depth[min]=$(( ${#path_parts[@]} - 1 ))

mapfile -t files < <(find "${if[dn]}" -exec printf '%q\n' {} + 2>&-)

for (( i = 0; i < ${#files[@]}; i++ )); do
	eval if[fn]="${files[${i}]}"

	mapfile -d'/' -t path_parts <<<"${if[fn]}"
	depth[tmp]=$(( ${#path_parts[@]} - 1 ))
	depth[diff]=$(( depth[tmp] - depth[min] ))

	if [[ ${depth[diff]} -gt ${depth[max]} ]]; then
		depth[max]="${depth[diff]}"
	fi
done

unset -v "${vars[@]}"

for (( i = depth[max]; i > 0; i-- )); do
	mapfile -t files < <(find "${if[dn]}" -mindepth "$i" -maxdepth "$i" -exec printf '%q\n' {} + 2>&-)

	for (( j = 0; j < ${#files[@]}; j++ )); do
		eval if[fn]="${files[${j}]}"
		of[dn]=$(dirname "${if[fn]}")
		if[bn]=$(basename "${if[fn]}")

		of[upper]="${if[bn]^^}"
		of[lower]="${if[bn],,}"

		of[bn]="${of[${case}]}"

		of[fn]="${of[dn]}/${of[bn]}"

		if [[ ${of[bn]} != "${if[bn]}" ]]; then
			printf '%s\n' "${of[fn]}"
			mv -n "${if[fn]}" "${of[fn]}"
		fi
	done
done
