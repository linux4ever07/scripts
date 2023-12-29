#!/bin/bash

# This script will recursively change the file / directory names under
# the directory specified, to remove quotes and double quotes from file
# / directory names.

set -eo pipefail

# Creates a function, called 'usage', which will print usage
# instructions and then quit.
usage () {
	printf '\n%s\n\n' "Usage: $(basename "$0") [dir]"
	exit
}

if [[ ! -d $1 ]]; then
	usage
fi

declare -a vars files path_parts
declare -A if of depth

vars=('files' 'path_parts')

if[dn]=$(readlink -f "$1")

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
	mapfile -t files < <(find "${if[dn]}" -mindepth "$i" -maxdepth "$i" -exec printf '%q\n' {} + 2>&-)

	for (( j = 0; j < ${#files[@]}; j++ )); do
		eval if[fn]="${files[${j}]}"
		of[dn]=$(dirname "${if[fn]}")
		if[bn]=$(basename "${if[fn]}")

		of[bn]=$(printf '%s' "$bn" | tr -d "'" | tr -d '"')
		of[fn]="${of[dn]}/${of[bn]}"

		if [[ ${of[bn]} != "${if[bn]}" ]]; then
			printf '%s\n' "${of[fn]}"
			mv -n "${if[fn]}" "${of[fn]}"
		fi
	done
done
