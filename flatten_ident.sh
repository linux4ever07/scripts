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
declare -A input output depth regex

input[dn]=$(readlink -f "$1")

regex[fn]='^(.*)\.([^.]*)$'

vars=('files' 'dirs' 'path_parts')

session="${RANDOM}-${RANDOM}"

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
	mapfile -t dirs < <(find "${input[dn]}" -type d -mindepth "$i" -maxdepth "$i" -exec printf '%q\n' {} + 2>&-)

	for (( j = 0; j < ${#dirs[@]}; j++ )); do
		eval input[fn]="${dirs[${j}]}"
		output[dn]=$(dirname "${input[fn]}")
		input[bn]=$(basename "${input[fn]}")

		unset -v input[ext] output[ext]

		mapfile -t files < <(compgen -G "${input[fn]}/*")

		if [[ ${#files[@]} -ne 1 ]]; then
			continue
		fi

		output[fn]="${files[0]}"
		output[bn]=$(basename "${output[fn]}")

		if [[ ${input[bn]} =~ ${regex[fn]} ]]; then
			input[bn]="${BASH_REMATCH[1]}"
			input[ext]="${BASH_REMATCH[2]}"
		fi

		if [[ ${output[bn]} =~ ${regex[fn]} ]]; then
			output[bn]="${BASH_REMATCH[1]}"
			output[ext]="${BASH_REMATCH[2]}"
		fi

		if [[ ${input[bn]} != "${output[bn]}" ]]; then
			continue
		fi

		printf '%s\n' "${input[fn]}"

		if [[ -n ${input[ext]} ]]; then
			output[fn]="${input[bn]}-${session}.${input[ext]}"
		else
			output[fn]="${input[bn]}-${session}"
		fi

		output[fn]="${output[dn]}/${output[fn]}"

		mv -n "${input[fn]}" "${output[fn]}"
		mv -n "${output[fn]}"/* "${output[dn]}"
		rm -r "${output[fn]}"
	done
done
