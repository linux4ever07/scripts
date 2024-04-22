#!/bin/bash

# This script is meant to print a specific function in a Bash script
# given to it as argument.

# Creates a function, called 'usage', which will print usage
# instructions and then quit.
usage () {
	printf '\n%s\n\n' "Usage: $(basename "$0") [file] [function name]"
	exit
}

if [[ ! -f $1 || -z $2 ]]; then
	usage
fi

declare if switch line
declare -a lines
declare -A regex

if=$(readlink -f "$1")

regex[start]="^([[:blank:]]*)${2}[[:blank:]]*\(\) \{"

switch=0

mapfile -t lines < <(tr -d '\r' <"$if")

printf '\n'

for (( i = 0; i < ${#lines[@]}; i++ )); do
	line="${lines[${i}]}"

	if [[ $line =~ ${regex[start]} ]]; then
		switch=1
		regex[stop]="^${BASH_REMATCH[1]}\}"
	fi

	if [[ $switch -eq 0 ]]; then
		continue
	fi

	printf '%s\n' "$line"

	if [[ $line =~ ${regex[stop]} ]]; then
		switch=0
		printf '\n'
	fi
done
