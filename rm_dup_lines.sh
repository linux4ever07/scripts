#!/bin/bash

# This script removes duplicate lines from IRC logs in the current
# directory.

set -eo pipefail

declare session line line_tmp
declare -a clients files lines
declare -A input output regex

# The order of clients is like this, because the Konversation regex is
# similar to the IRCCloud one and needs to be tried before it. When
# similar, the most complex regex needs to be tried first.
clients=('konversation' 'irccloud' 'hexchat' 'irssi')

regex[hexchat]='^[[:alpha:]]+ [[:digit:]]+ [[:digit:]]+:[[:digit:]]+:[[:digit:]]+ (.*)$'
regex[irccloud]='^\[[^]]+\][[:blank:]]+(.*)$'
regex[irssi]='^[[:digit:]]+:[[:digit:]]+[[:blank:]]+(.*)$'
regex[konversation]='^\[[^]]+\][[:blank:]]+\[[^]]+\][[:blank:]]+(.*)$'

session="${RANDOM}-${RANDOM}"
output[dn]="/dev/shm/rm_dup_lines-${session}"

mkdir "${output[dn]}"

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
	input[fn]="${files[${i}]}"
	input[bn]=$(basename "${input[fn]}")
	output[fn]="${output[dn]}/${input[bn]}"

	declare previous

	touch "${output[fn]}"

	mapfile -t lines < <(tr -d '\r' <"${input[fn]}")

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

		printf '%s\n' "$line" >> "${output[fn]}"
	done

	unset -v previous regex[client]

	touch -r "${input[fn]}" "${output[fn]}"
	mv "${output[fn]}" "${input[fn]}"
done

rm -rf "${output[dn]}"
