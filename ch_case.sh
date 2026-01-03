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
declare -A input output depth

vars=('files' 'path_parts')

input[dn]=$(readlink -f "$1")

case="$2"

depth[max]=0

pause_msg="
You're about to recursively change all the file / directory names
under \"${input[dn]}\" to ${case} case.

Are you sure? [y/n]: "

read -p "$pause_msg"

if [[ $REPLY != 'y' ]]; then
	exit
fi

printf '\n'

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

		output[upper]="${input[bn]^^}"
		output[lower]="${input[bn],,}"

		output[bn]="${output[${case}]}"

		output[fn]="${output[dn]}/${output[bn]}"

		if [[ ${output[bn]} != "${input[bn]}" ]]; then
			printf '%s\n' "${output[fn]}"
			mv -n "${input[fn]}" "${output[fn]}"
		fi
	done
done
