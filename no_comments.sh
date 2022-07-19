#!/bin/bash

# This script is just meant to read script files, but without the
# comments.

if=$(readlink -f "$1")

regex='^([[:space:]]*)(#+)'

mapfile -t lines < <(grep -Ev "$regex" "$if")

for (( i = 0; i < ${#lines[@]}; i++ )); do
	printf '%s\n' "${lines[${i}]}"
done
