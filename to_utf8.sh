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

declare if charset_of session

charset_of='UTF-8'
session="${RANDOM}-${RANDOM}"

declare -A regex

regex[fn]='^(.*)\.([^.]*)$'
regex[charset1]='([^; ]+)$'
regex[charset2]='^charset=(.*)$'

# Creates a function, called 'read_decode_fn', which tries to figure out
# the correct character set encoding of the input file. If it succeeds,
# it will encode that file to UTF-8.
read_decode_fn () {
	declare charset_if of

	charset_if=$(file -bi "$if")

	if [[ -z $charset_if ]]; then
		return
	fi

	if [[ ! $charset_if =~ ${regex[charset1]} ]]; then
		return
	fi

	charset_if="${BASH_REMATCH[1]}"

	if [[ ! $charset_if =~ ${regex[charset2]} ]]; then
		return
	fi

	charset_if="${BASH_REMATCH[1]^^}"

	if [[ $if =~ ${regex[fn]} ]]; then
		of="${BASH_REMATCH[1]}-${session}.${BASH_REMATCH[2]}"
	else
		of="${if}-${session}"
	fi

	iconv -f "$charset_if" -t "$charset_of" -o "$of" "$if"

	printf '\n(%s -> %s) %s %s\n\n' "$charset_if" "$charset_of" 'Wrote file:' "$of"

	unset -v charset_if of
}

for (( i = 0; i < ${#files[@]}; i++ )); do
	if="${files[${i}]}"

	read_decode_fn
done
