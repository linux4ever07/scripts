#!/bin/bash

# This script removes duplicate lines from IRC logs in the current
# directory.

set -eo pipefail

declare session line line_tmp
declare -a clients files lines
declare -A if of regex

clients=('hexchat' 'irccloud' 'irssi' 'konversation')

regex[hexchat]='^[[:alpha:]]+ [0-9]+ [0-9]+:[0-9]+:[0-9]+(.*)$'
regex[irccloud]='^\[[0-9]+-[0-9]+-[0-9]+ [0-9]+:[0-9]+:[0-9]+\](.*)$'
regex[irssi]='^[0-9]+:[0-9]+(.*)$'
regex[konversation]='^\[[[:alpha:]]+, [[:alpha:]]+ [0-9]+, [0-9]+\] \[[0-9]+:[0-9]+:[0-9]+ [[:alpha:]]+ [[:alpha:]]+\](.*)$'

session="${RANDOM}-${RANDOM}"
of[dn]="/dev/shm/rm_dup_lines-${session}"

mkdir "${of[dn]}"

# Creates a function, called 'get_client', which will figure out which
# client was used to generate the IRC log in question, to be able to
# parse it correctly.
get_client () {
	declare switch client

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
	if[fn]="${files[${i}]}"
	if[bn]=$(basename "${if[fn]}")
	of[fn]="${of[dn]}/${if[bn]}"

	declare previous

	touch "${of[fn]}"

	mapfile -t lines < <(tr -d '\r' <"${if[fn]}")

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

		printf '%s\n' "$line" >> "${of[fn]}"
	done

	unset -v previous regex[client]

	touch -r "${if[fn]}" "${of[fn]}"
	mv "${of[fn]}" "${if[fn]}"
done

rm -rf "${of[dn]}"
