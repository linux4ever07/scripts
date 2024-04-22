#!/bin/bash

# This script reads 2 text files. The first file is the input file, and
# the second is the output. Every line present in both files is removed
# from the output file.

set -eo pipefail

# Creates a function, called 'usage', which will print usage
# instructions and then quit.
usage () {
	printf '\n%s\n\n' "Usage: $(basename "$0") [file 1] [file 2]"
	exit
}

if [[ ! -f $1 || ! -f $2 ]]; then
	usage
fi

declare session line_in line_out
declare -a lines_in lines_out
declare -A if of

session="${RANDOM}-${RANDOM}"

if[fn]=$(readlink -f "$1")
of[fn]=$(readlink -f "$2")
of[fn_tmp]="${of[fn]%.*}-${session}.txt"

mapfile -t lines_in < <(tr -d '\r' <"${if[fn]}")
mapfile -t lines_out < <(tr -d '\r' <"${of[fn]}")

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
		printf '%s\n' "$line_out" | tee -a "${of[fn_tmp]}"
	fi
done

touch -r "${of[fn]}" "${of[fn_tmp]}"
mv "${of[fn_tmp]}" "${of[fn]}"
