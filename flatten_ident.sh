#!/bin/bash

# This script is meant to find all sub-directories in the directory
# given as argument, and flatten them, if they contain just 1 file that
# has the same name as the directory.

set -eo pipefail

# Creates a function, called 'usage', which will print usage
# instructions and then quit.
usage () {
	printf '\n%s\n\n' "Usage: $(basename "$0") [dir]"
	exit
}

if [[ $# -ne 1 ]]; then
	usage
fi

if [[ ! -d $1 ]]; then
	usage
fi

declare session
declare -a vars files dirs path_parts
declare -A if of depth regex

vars=('files' 'dirs' 'path_parts')

session="${RANDOM}-${RANDOM}"

if[dn]=$(readlink -f "$1")

regex[fn]='^(.*)\.([^.]*)$'

depth[max]=0

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
	mapfile -t dirs < <(find "${if[dn]}" -type d -mindepth "$i" -maxdepth "$i" -exec printf '%q\n' {} + 2>&-)

	for (( j = 0; j < ${#dirs[@]}; j++ )); do
		eval if[fn]="${dirs[${j}]}"
		of[dn]=$(dirname "${if[fn]}")
		if[bn]=$(basename "${if[fn]}")

		unset -v if[ext] of[ext]

		mapfile -t files < <(compgen -G "${if[fn]}/*")

		if [[ ${#files[@]} -ne 1 ]]; then
			continue
		fi

		of[fn]="${files[0]}"
		of[bn]=$(basename "${of[fn]}")

		if [[ ${if[bn]} =~ ${regex[fn]} ]]; then
			if[bn]="${BASH_REMATCH[1]}"
			if[ext]="${BASH_REMATCH[2]}"
		fi

		if [[ ${of[bn]} =~ ${regex[fn]} ]]; then
			of[bn]="${BASH_REMATCH[1]}"
			of[ext]="${BASH_REMATCH[2]}"
		fi

		if [[ ${if[bn]} != "${of[bn]}" ]]; then
			continue
		fi

		printf '%s\n' "${if[fn]}"

		if [[ -n ${if[ext]} ]]; then
			of[fn]="${if[bn]}-${session}.${if[ext]}"
		else
			of[fn]="${if[bn]}-${session}"
		fi

		of[fn]="${of[dn]}/${of[fn]}"

		mv -n "${if[fn]}" "${of[fn]}"
		mv -n "${of[fn]}"/* "${of[dn]}"
		rm -r "${of[fn]}"
	done
done
