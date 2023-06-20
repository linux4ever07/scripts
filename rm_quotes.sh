#!/bin/bash

# This script will recursively change the file / directory names under
# the directory specified, to remove quotes and double quotes from file
# / directory names.

set -eo pipefail

usage () {
	printf '\n%s\n\n' "Usage: $(basename "$0") [dir]"
	exit
}

if [[ ! -d $1 ]]; then
	usage
fi

if_dn=$(readlink -f "$1")
depth_max=0

mapfile -d'/' -t path_parts <<<"$if_dn"
depth_og=$(( ${#path_parts[@]} - 1 ))

mapfile -t files < <(find "$if_dn" 2>&-)

for (( i = 0; i < ${#files[@]}; i++ )); do
	fn="${files[${i}]}"

	mapfile -d'/' -t path_parts <<<"$fn"
	depth_tmp=$(( ${#path_parts[@]} - 1 ))
	depth_diff=$(( depth_tmp - depth_og ))

	if [[ $depth_diff -gt $depth_max ]]; then
		depth_max="$depth_diff"
	fi
done

unset -v files path_parts depth_og depth_tmp depth_diff

for (( i = depth_max; i > 0; i-- )); do
	mapfile -t files < <(find "$if_dn" -mindepth "$i" -maxdepth "$i" 2>&-)

	for (( j = 0; j < ${#files[@]}; j++ )); do
		fn="${files[${j}]}"
		dn=$(dirname "$fn")
		bn=$(basename "$fn")

		new_bn=$(printf '%s' "$bn" | tr -d "'" | tr -d '"')
		new_fn="${dn}/${new_bn}"

		if [[ $new_bn != "$bn" ]]; then
			printf '%s\n' "$new_fn"
			mv -n "$fn" "$new_fn"
		fi
	done
done
