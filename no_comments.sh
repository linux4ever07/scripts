#!/bin/bash

# This script is just meant to read script files, but without the
# comments.

# Creates a function, called 'usage', which will print usage
# instructions and then quit.
usage () {
	printf '\n%s\n\n' "Usage: $(basename "$0") [file]"
	exit
}

if [[ ! -f $1 ]]; then
	usage
fi

declare -A input output regex

input[fn]=$(readlink -f "$1")

regex[comment]='^[[:blank:]]*#+'

tr -d '\r' <"${input[fn]}" | grep -Ev "${regex[comment]}"
