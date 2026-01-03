#!/bin/bash

# This script converts text files to the UTF-8 charset.

# To list available character set encodings:
# iconv -l

set -eo pipefail

# Creates a function, called 'usage', which will print usage
# instructions and then quit.
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

declare output_charset session
declare -A input output regex

output_charset='UTF-8'
session="${RANDOM}-${RANDOM}"

regex[fn]='^(.*)\.([^.]*)$'
regex[charset1]='([^; ]+)$'
regex[charset2]='^charset=(.*)$'

# Creates a function, called 'read_decode_fn', which tries to figure out
# the correct character set encoding of the input file. If it succeeds,
# it will encode that file to UTF-8.
read_decode_fn () {
	declare input_charset

	input_charset=$(file -bi "${input[fn]}")

	if [[ -z $input_charset ]]; then
		return
	fi

	if [[ ! $input_charset =~ ${regex[charset1]} ]]; then
		return
	fi

	input_charset="${BASH_REMATCH[1]}"

	if [[ ! $input_charset =~ ${regex[charset2]} ]]; then
		return
	fi

	input_charset="${BASH_REMATCH[1]^^}"

	if [[ ${input[fn]} =~ ${regex[fn]} ]]; then
		output[fn]="${BASH_REMATCH[1]}-${session}.${BASH_REMATCH[2]}"
	else
		output[fn]="${input[fn]}-${session}"
	fi

	iconv -f "$input_charset" -t "$output_charset" -o "${output[fn]}" "${input[fn]}"

	printf '\n(%s -> %s) %s %s\n\n' "$input_charset" "$output_charset" 'Wrote file:' "${output[fn]}"

	unset -v input_charset
}

for (( i = 0; i < ${#files[@]}; i++ )); do
	input[fn]="${files[${i}]}"

	read_decode_fn
done
