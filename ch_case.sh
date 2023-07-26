#!/bin/bash

# This script will recursively change the file / directory names under
# the directory specified to either upper or lower case.

# The use case for this may be for example to change MS-DOS file names
# (for programs and games) to whatever format you prefer, upper case or
# lower case. I'm a *nix user, so I prefer lower case. Since MS-DOS is
# case insensitive it doesn't matter which format you use, as it will
# show up as upper case from within DOS anyway.

set -eo pipefail

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

if_dn=$(readlink -f "$1")

case="$2"

declare -a vars1 vars2

vars1=('depth_og' 'depth_tmp' 'depth_diff')
vars2=('files' 'path_parts')

depth_max=0

pause_msg="
You're about to recursively change all the file / directory names
under \"${if_dn}\" to ${case} case.

Are you sure? [y/n]: "

read -p "$pause_msg"

if [[ $REPLY != 'y' ]]; then
	exit
fi

printf '\n'

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

		if [[ $case == 'upper' ]]; then
			new_bn="${bn^^}"
		elif [[ $case == 'lower' ]]; then
			new_bn="${bn,,}"
		fi

		new_fn="${dn}/${new_bn}"

		if [[ $new_bn != "$bn" ]]; then
			printf '%s\n' "$new_fn"
			mv -n "$fn" "$new_fn"
		fi
	done
done
