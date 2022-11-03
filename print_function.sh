#!/bin/bash

# This script is meant to print a specific function in a Bash script
# given to it as argument.

if=$(readlink -f "$1")

usage () {
	printf '\n%s\n\n' "Usage: $(basename "$0") [file] [function name]"
	exit
}

if [[ ! -f $if || -z $2 ]]; then
	usage
fi

regex_start="^([[:blank:]]*)${2} *\(\) \{"
declare regex_stop

switch=0

mapfile -t lines <"$if"

printf '\n'

for (( i = 0; i < ${#lines[@]}; i++ )); do
	line="${lines[${i}]}"

	if [[ $line =~ $regex_start ]]; then
		regex_stop="^${BASH_REMATCH[1]}\{"
		switch=1
	fi

	if [[ $switch -eq 1 ]]; then
		printf '%s\n' "$line"

		if [[ $line =~ $regex_stop ]]; then
			switch=0

			printf '\n'
		fi
	fi
done
