#!/bin/bash

# This script converts text files to the UTF-8 charset.

# To list available character set encodings:
# iconv -l

set -eo pipefail

# Creates a function called 'usage', which prints usage and then quits.
usage () {
	printf '\n%s\n\n' "Usage: $(basename "$0") [txt]"
	exit
}

if [[ $# -eq 0 ]]; then
	usage
fi

declare -a files

while [[ $# -gt 0 ]]; do
	if [[ -f $1 ]]; then
		files+=("$(readlink -f "$1")")
	else
		usage
	fi

	shift
done

if [[ ${#files[@]} -eq 0 ]]; then
	usage
fi

declare session

session="${RANDOM}-${RANDOM}"

declare -A regex

regex[charset]='charset=(.*)[[:blank:]]*$'
regex[fn]='^(.*)\.([^.]*)$'

# Creates a function called 'read_decode_fn', which tries to figure out
# the correct character set encoding of the input file. If it succeeds,
# it will encode that file to UTF-8.
read_decode_fn () {
	declare charset of
	declare -a cmd_stdout

	mapfile -t cmd_stdout < <(file -i "$fn")

	if [[ ${#cmd_stdout[@]} -eq 0 ]]; then
		return
	fi

	if [[ ! ${cmd_stdout[0]} =~ ${regex[charset]} ]]; then
		return
	fi

	charset="${BASH_REMATCH[1]^^}"

	if [[ $fn =~ ${regex[fn]} ]]; then
		of="${BASH_REMATCH[1]}-${session}.${BASH_REMATCH[2]}"
	else
		of="${fn}-${session}"
	fi

	iconv -f "$charset" -t 'UTF-8' -o "$of" "$fn"
}

for (( i = 0; i < ${#files[@]}; i++ )); do
	fn="${files[${i}]}"

	read_decode_fn
done
