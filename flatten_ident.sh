#!/bin/bash

# This script is meant to find all sub-directories in the directory
# given as argument, and flatten them, if they contain just 1 file that
# has the same name as the directory.

# Creates a function called 'usage', which will print usage instructions
# and then quit.
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

if_dn=$(readlink -f "$1")

session="${RANDOM}-${RANDOM}"

declare -a dirs files
declare -A regex

regex[fn]='^(.*)\.([^.]*)$'

depth_max=0

mapfile -d'/' -t path_parts <<<"$dir"
depth_og=$(( ${#path_parts[@]} - 1 ))

mapfile -t files < <(find "$dir" -exec printf '%q\n' {} + 2>&-)

for (( i = 0; i < ${#files[@]}; i++ )); do
	eval fn="${files[${i}]}"

	mapfile -d'/' -t path_parts <<<"$fn"
	depth_tmp=$(( ${#path_parts[@]} - 1 ))
	depth_diff=$(( depth_tmp - depth_og ))

	if [[ $depth_diff -gt $depth_max ]]; then
		depth_max="$depth_diff"
	fi
done

unset -v files path_parts depth_og depth_tmp depth_diff

mv_print () {
	declare if of

	printf '%s\n' "$fn"

	if [[ -n $ext ]]; then
		of="${bn}-${session}.${ext}"
	else
		of="${bn}-${session}"
	fi

	of="${dn_dn}/${of}"

	mv -n "$fn" "$of"
	rm -r "$dn"

	if [[ -n $ext ]]; then
		if="${bn}.${ext}"
	else
		if="$bn"
	fi

	if="${dn_dn}/${if}"

	mv -n "$of" "$if"
}

mapfile -t dirs < <(find "$if_dn" -type d 2>&-)

for (( i = 0; i < ${#dirs[@]}; i++ )); do
	dn="${dirs[${i}]}"
	dn_dn=$(dirname "$dn")
	dn_bn=$(basename "$dn")

	declare ext

	mapfile -t files < <(compgen -G "${dn}/*")

	if [[ ${#files[@]} -ne 1 ]]; then
		continue
	fi

	fn="${files[0]}"
	bn=$(basename "$fn")

	if [[ $bn == "$dn_bn" ]]; then
		mv_print
		continue
	fi

	if [[ $bn =~ ${regex[fn]} ]]; then
		bn="${BASH_REMATCH[1]}"
		ext="${BASH_REMATCH[2]}"
	fi

	if [[ $bn == "$dn_bn" ]]; then
		mv_print
		continue
	fi

	unset -v dn dn_dn dn_bn fn bn ext
done
