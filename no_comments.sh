#!/bin/bash

# This script is just meant to read script files, but without the
# comments.

if [[ ! -f $1 ]]; then
	printf '\n%s\n\n' "Usage: $(basename "$0") [file]"
	exit
fi

if=$(readlink -f "$1")

regex='^([[:blank:]]*)(#+)'

mapfile -t lines < <(tr -d '\r' <"$if" | grep -Ev "$regex")

printf '%s\n' "${lines[@]}"
