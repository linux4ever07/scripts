#!/bin/bash

# This script removes duplicate lines from IRC logs in the current
# directory.

set -eo pipefail

declare -a clients lines
declare -A regex

clients=('hexchat' 'irccloud' 'irssi' 'konversation')

regex[hexchat]='^[[:alpha:]]+ [0-9]+ [0-9]+:[0-9]+:[0-9]+(.*)$'
regex[irccloud]='^\[[0-9]+-[0-9]+-[0-9]+ [0-9]+:[0-9]+:[0-9]+\](.*)$'
regex[irssi]='^[0-9]+:[0-9]+(.*)$'
regex[konversation]='^\[[[:alpha:]]+, [[:alpha:]]+ [0-9]+, [0-9]+\] \[[0-9]+:[0-9]+:[0-9]+ [[:alpha:]]+ [[:alpha:]]+\](.*)$'

session="${RANDOM}-${RANDOM}"
dn="/dev/shm/rm_dup_lines-${session}"

mkdir "$dn"

# Creates a function called 'get_client', which will figure out which
# client was used to generate the IRC log in question, to be able to
# parse it correctly.
get_client () {
	declare switch

	switch=0

	for (( z = 0; z < ${#lines[@]}; z++ )); do
		line="${lines[${z}]}"

		for client in "${clients[@]}"; do
			if [[ ! $line =~ ${regex[${client}]} ]]; then
				continue
			fi

			regex[client]="${regex[${client}]}"
			switch=1

			break
		done

		if [[ $switch -eq 1 ]]; then
			break
		fi
	done
}

mapfile -t files < <(find "$PWD" -type f -iname "*.log" -o -iname "*.txt" 2>&-)

for (( i = 0; i < ${#files[@]}; i++ )); do
	fn="${files[${i}]}"
	bn=$(basename "$fn")

	fn_out="${dn}/${bn}"

	touch "$fn_out"

	mapfile -t lines < <(tr -d '\r' <"$fn")

	get_client

	for (( j = 0; j < ${#lines[@]}; j++ )); do
		line="${lines[${j}]}"
		line_tmp="$line"

		if [[ -n ${regex[client]} ]]; then
			if [[ $line =~ ${regex[client]} ]]; then
				line_tmp="${BASH_REMATCH[1]}"
			fi
		fi

		if [[ $j -ge 1 ]]; then
			if [[ $line_tmp == "$previous" ]]; then
				continue
			fi
		fi

		previous="$line_tmp"

		printf '%s\n' "$line" >> "$fn_out"
	done

	unset -v previous regex[client]

	touch -r "$fn" "$fn_out"
	mv "$fn_out" "$fn"
done

rm -rf "$dn"
