#!/bin/bash

# This script will recursively change the file / directory names under
# the directory specified, to remove newlines from file / directory
# names.

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
declare -A input output depth

input[dn]=$(readlink -f "$1")

vars=('files' 'path_parts')

depth[max]=0

mapfile -d'/' -t path_parts <<<"${input[dn]}"
depth[min]=$(( ${#path_parts[@]} - 1 ))

mapfile -t files < <(find "${input[dn]}" -exec printf '%q\n' {} + 2>&-)

for (( i = 0; i < ${#files[@]}; i++ )); do
	eval input[fn]="${files[${i}]}"

	mapfile -d'/' -t path_parts <<<"${input[fn]}"
	depth[tmp]=$(( ${#path_parts[@]} - 1 ))
	depth[diff]=$(( depth[tmp] - depth[min] ))

	if [[ ${depth[diff]} -gt ${depth[max]} ]]; then
		depth[max]="${depth[diff]}"
	fi
done

unset -v "${vars[@]}"

for (( i = depth[max]; i > 0; i-- )); do
	mapfile -t files < <(find "${input[dn]}" -mindepth "$i" -maxdepth "$i" -exec printf '%q\n' {} + 2>&-)

	for (( j = 0; j < ${#files[@]}; j++ )); do
		eval input[fn]="${files[${j}]}"
		output[dn]=$(dirname "${input[fn]}")
		input[bn]=$(basename "${input[fn]}")

		output[bn]=$(tr -d '\r\n' <<<"${input[bn]}")
		output[fn]="${output[dn]}/${output[bn]}"

		if [[ ${output[bn]} != "${input[bn]}" ]]; then
			printf '%s\n' "${output[fn]}"
			mv -n "${input[fn]}" "${output[fn]}"
		fi
	done
done
