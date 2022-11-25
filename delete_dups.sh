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

if [[ $# -lt 2 ]]; then
	usage
fi

declare -a dirs

for dn in "$@"; do
	if [[ ! -d $dn ]]; then
		usage
	fi

	dirs+=("$(readlink -f "$dn")")
done

declare -A md5s

dn_if="${dirs[0]}"
unset -v dirs[0]

mapfile -t files < <(find "$dn_if" -type f -exec printf '%q\n' {} \; 2>&-)

for (( i = 0; i < ${#files[@]}; i++ )); do
	eval f="${files[${i}]}"
	f_bn=$(basename "$f")

	md5=$(md5sum -b "$f")
	md5="${md5%% *}"
	md5s["${md5}"]="$f_bn"
done

for dn in "${dirs[@]}"; do
	mapfile -t files < <(find "$dn" -type f -exec printf '%q\n' {} \; 2>&-)

	for (( i = 0; i < ${#files[@]}; i++ )); do
		eval f="${files[${i}]}"
		f_bn=$(basename "$f")

		md5=$(md5sum -b "$f")
		md5="${md5%% *}"

		if [[ -n ${md5s[${md5}]} ]]; then
			if [[ ${md5s[${md5}]} == "$f_bn" ]]; then
				printf '%s\n' "$f"
				rm -f "$f"
			fi
		fi
	done
done
