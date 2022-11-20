#!/bin/bash

# This script is just meant to read script files, but without the
# comments.

if=$(readlink -f "$1")

if [[ ! -f $if ]]; then
	printf '\n%s\n\n' "Usage: $(basename "$0") [file]"
	exit
fi

regex='^([[:blank:]]*)(#+)'

mapfile -t lines < <(grep -Ev "$regex" "$if")

printf '%s\n' "${lines[@]}"
