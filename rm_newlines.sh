#!/bin/bash

# This script will recursively change the file / directory names under
# the directory specified, to remove newlines from file / directory
# names.

set -eo pipefail

# Creates a function called 'usage', which will print usage instructions
# and then quit.
usage () {
	printf '\n%s\n\n' "Usage: $(basename "$0") [dir]"
	exit
}

if [[ ! -d $1 ]]; then
	usage
fi

if_dn=$(readlink -f "$1")

declare -a vars1 vars2

vars1=('depth_og' 'depth_tmp' 'depth_diff')
vars2=('files' 'path_parts')

depth_max=0

mapfile -d'/' -t path_parts <<<"$if_dn"
depth_og=$(( ${#path_parts[@]} - 1 ))

mapfile -t files < <(find "$if_dn" -exec printf '%q\n' {} + 2>&-)

for (( i = 0; i < ${#files[@]}; i++ )); do
	eval fn="${files[${i}]}"

	mapfile -d'/' -t path_parts <<<"$fn"
	depth_tmp=$(( ${#path_parts[@]} - 1 ))
	depth_diff=$(( depth_tmp - depth_og ))

	if [[ $depth_diff -gt $depth_max ]]; then
		depth_max="$depth_diff"
	fi
done

unset -v "${vars1[@]}" "${vars2[@]}"

for (( i = depth_max; i > 0; i-- )); do
	mapfile -t files < <(find "$if_dn" -mindepth "$i" -maxdepth "$i" -exec printf '%q\n' {} + 2>&-)

	for (( j = 0; j < ${#files[@]}; j++ )); do
		eval fn="${files[${j}]}"
		dn=$(dirname "$fn")
		bn=$(basename "$fn")

		new_bn=$(tr -d "\r\n" <<<"$bn")
		new_fn="${dn}/${new_bn}"

		if [[ $new_bn != "$bn" ]]; then
			printf '%s\n' "$new_fn"
			mv -n "$fn" "$new_fn"
		fi
	done
done
