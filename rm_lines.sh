#!/bin/bash

# This script reads 2 text files. The first file is the input file, and
# the second is the output. Every line present in both files is removed
# from the output file.

set -eo pipefail

# Creates a function called 'usage', which will print usage and quit.
usage () {
	printf '\n%s\n\n' "Usage: $(basename "$0") [file 1] [file 2]"
	exit
}

if [[ ! -f $1 || ! -f $2 ]]; then
	usage
fi

fn_in=$(readlink -f "$1")
fn_out=$(readlink -f "$2")

session="${RANDOM}-${RANDOM}"
fn_tmp="${fn_out%.*}-${session}.txt"

mapfile -t lines_in < <(tr -d '\r' <"$fn_in")
mapfile -t lines_out < <(tr -d '\r' <"$fn_out")

declare switch

for (( i = 0; i < ${#lines_out[@]}; i++ )); do
	line_out="${lines_out[${i}]}"

	switch=0

	for (( j = 0; j < ${#lines_in[@]}; j++ )); do
		line_in="${lines_in[${j}]}"

		if [[ $line_out == "$line_in" ]]; then
			switch=1

			break
		fi
	done

	if [[ $switch -eq 0 ]]; then
		printf '%s\n' "$line_out" | tee -a "$fn_tmp"
	fi
done

touch -r "$fn_out" "$fn_tmp"
mv "$fn_tmp" "$fn_out"
