#!/bin/bash

# This script takes at least two directories as arguments, checks the
# MD5 hash of all the files in the first directory, and then uses that
# list to delete duplicates from the other directories. Only files that
# both have the same name and the same MD5 hash will be considered
# duplicates.

set -eo pipefail

usage () {
	printf '\n%s\n\n' "Usage: $(basename "$0") [source dir] [dirs...]"
	exit
}

if [[ $# -eq 0 ]]; then
	usage
fi

declare -a dirs

for dn in "$@"; do
	if [[ ! -d $dn ]]; then
		usage
	fi

	dirs+=("$(readlink -f "$dn")")
done

if [[ ${#dirs[@]} -lt 2 ]]; then
	usage
fi

declare -A md5s

dn_if="${dirs[0]}"
unset -v dirs[0]

mapfile -t files < <(find "$dn_if" -type f -exec printf '%q\n' {} + 2>&-)

for (( i = 0; i < ${#files[@]}; i++ )); do
	eval fn="${files[${i}]}"
	bn=$(basename "$fn")

	md5=$(md5sum -b "$fn")
	md5="${md5%% *}"
	md5s["${md5}"]="$bn"
done

for dn in "${dirs[@]}"; do
	mapfile -t files < <(find "$dn" -type f -exec printf '%q\n' {} + 2>&-)

	for (( i = 0; i < ${#files[@]}; i++ )); do
		eval fn="${files[${i}]}"
		bn=$(basename "$fn")

		md5=$(md5sum -b "$fn")
		md5="${md5%% *}"

		if [[ -z ${md5s[${md5}]} ]]; then
			continue
		fi

		if [[ ${md5s[${md5}]} == "$bn" ]]; then
			printf '%s\n' "$fn"
			rm -f "$fn"
		fi
	done
done
