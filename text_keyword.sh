#!/bin/bash

# This script checks text documents, and searches for certain keywords
# (stored in an array) in all the documents, and shows the matching
# line, surrounded by 10 preceding lines and 10 following lines (with
# accompanying line numbers). Then the user is asked to select the range
# of lines to be removed from each document. Those lines are also added
# to the file name stored in the 'fn_out' variable.

# This script is a work in progress, and at the moment it has
# information stored in variables that's specific, and hence it will not
# work in a generalized fashion. I'm planning to make it more
# generalized eventually, but for now I'm keeping it as a demonstration
# on how to accomplish similar tasks.

# The goal of the script right now is to find all the mentions of video
# games among my notes, and collect all that into a single document.
# It's part of my ongoing mission to organize my files and reduce
# clutter.

set -eo pipefail

declare dn_in dn_out fn_in fn_out fn_tmp bn keyword line_in line_out number session
declare -a files_in files_out dirs keywords lines_in lines_out selected
declare -A regex

session="${RANDOM}-${RANDOM}"
#dn_in="${HOME}/Documents"
dn_in="${HOME}/text_keyword"
fn_out="${HOME}/games123.txt"
fn_tmp="/dev/shm/text_keyword-${session}.txt"

keywords=('(super){0,1} *nintendo *(64){0,1}' 'n *64' 'game[ -]*boy' 'gb([ca]){0,1}' 'sega' 'master[ -]*system' 'game[ -]*gear' 'mega[ -]*drive' 'genesis' 'saturn' 'dreamcast' 'neo[ -]*geo' 'pc[ -]*engine' 'turbografx' 'gamecube' 'playstation' 'ps *[1-5]' 'ouya' 'pce' 'arcade' 'mame' '(s){0,1}nes' 'pc' 'roms' '(computer|video){0,1}[ -]*game(s){0,1}' 'fav(orite|s){0,1}')

regex[range]='^([[:digit:]]+)-([[:digit:]]+)$'
regex[skip1]='^/home/lucifer/game_lists'
regex[skip2]='^/home/lucifer/unpacked/irc_logs'

mapfile -t dirs < <(find "/run/media/${USER}" -mindepth 1 -maxdepth 1 -type d)

dirs=("$HOME" "${dirs[@]}")

menu () {
	declare number_in number_out number_start number_stop range_start range_stop switch
	declare -a numbers

	clear

	switch=0

	number_in="$1"

	numbers=()

	number_start=$(( number_in - 10 ))
	number_stop=$(( number_in + 10 ))

	if [[ $number_start -lt 0 ]]; then
		number_start=0
	fi

	if [[ $number_stop -gt ${#lines_in[@]} ]]; then
		number_stop="${#lines_in[@]}"
	fi

	printf '\n*** %s ***\n\n' "$fn_in"

	for (( z = number_start; z < number_stop; z++ )); do
		line_out="${lines_in[${z}]}"

		numbers+=("$z")

		printf '%s: %s\n' "$z" "$line_out"
	done

	until [[ $switch -eq 1 ]]; do
		printf '\n\n(s) skip\n\n'

		read -p 'Select line range: '

		if [[ $REPLY =~ ${regex[range]} ]]; then
			range_start="${BASH_REMATCH[1]}"
			range_stop="${BASH_REMATCH[2]}"

			if [[ $range_start -gt $range_stop ]]; then
				continue
			fi

			if [[ $range_start -lt ${numbers[0]} ]]; then
				continue
			fi

			if [[ $range_stop -gt ${numbers[-1]} ]]; then
				continue
			fi

			printf '\nYou selected line range %s.\n' "$REPLY"

			read -p 'Are you sure? [y/n]: '

			if [[ $REPLY == 'y' ]]; then
				switch=1
			fi
		elif [[ $REPLY == 's' ]]; then
			return
		fi

		if [[ $switch -eq 1 ]]; then
			for (( z = range_start; z <= range_stop; z++ )); do
				selected+=("$z")
			done
		fi
	done
}

process_files () {
	if [[ ${#files_in[@]} -eq 0 ]]; then
		return
	fi

	for keyword in "${keywords[@]}"; do
		for (( i = 0; i < ${#files_in[@]}; i++ )); do
			fn_in="${files_in[${i}]}"

			selected=()

			mapfile -t lines_in < <(tr -d '\r' <"$fn_in")

			lines_out=("${lines_in[@]}")

			for (( j = 0; j < ${#lines_in[@]}; j++ )); do
				line_in="${lines_in[${j}]}"

				if [[ ${line_in,,} =~ $keyword ]]; then
					menu "$j"
				fi
			done

			if [[ ${#selected[@]} -gt 0 ]]; then
				for number in "${selected[@]}"; do
					printf '%s\n' "${lines_out[${number}]}" >> "$fn_out"
				done

				printf '\n***\n\n' >> "$fn_out"

				for number in "${selected[@]}"; do
					unset -v "lines_out[${number}]"
				done

				lines_out=("${lines_out[@]}")

				printf '%s\n' "${lines_out[@]}" > "$fn_tmp"

				touch -r "$fn_in" "$fn_tmp"
				mv "$fn_tmp" "$fn_in"
			fi
		done
	done
}

mapfile -t files_in < <(find "$dn_in" -mindepth 1 -maxdepth 1 -type f -iname "notes*.txt")

process_files

for dn_out in "${dirs[@]}"; do
	mapfile -t files_in < <(find "$dn_out" -mindepth 1 -maxdepth 1 -type f -iname "*.txt")

	files_out+=("${files_in[@]}")
done

files_in=("${files_out[@]}")
files_out=()

for (( i = 0; i < ${#files_in[@]}; i++ )); do
	fn_in="${files_in[${i}]}"
	bn="${fn_in##*/}"
	bn="${bn%.*}"

	if [[ -L $fn_in ]]; then
		continue
	fi

	if [[ $fn_in == "$fn_out" ]]; then
		continue
	fi

	if [[ $fn_in =~ ${regex[skip1]} ]]; then
		continue
	fi

	if [[ $fn_in =~ ${regex[skip2]} ]]; then
		continue
	fi

	for keyword in "${keywords[@]}"; do
		if [[ ${bn,,} =~ $keyword ]]; then
			files_out+=("$fn_in")

			break
		fi
	done
done

files_in=("${files_out[@]}")
files_out=()

process_files
