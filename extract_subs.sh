#!/bin/bash

# This script is meant to extract all the subtitles from MKV (Matroska)
# files. The output file name is the same as the input file name, only a
# random number is added to the name.

declare -a cmd files if_subs
declare -A if of

# Creates a function called 'usage', which will print a message and then
# quit.
usage () {
	declare -a msg

	msg[0]="You need mkvtoolnix installed to run this script."
	msg[1]="Usage: $(basename "$0") [mkv]"
	msg[2]="There are no subtitles in: ${if[bn]}"

	printf '\n%s\n\n' "${msg[${1}]}"

	exit
}

mapfile -t cmd < <(command -v mkvinfo mkvmerge)

if [[ ${#cmd[@]} -ne 2 ]]; then
	usage 0
fi

# The loop below handles the arguments to the script.
while [[ $# -gt 0 ]]; do
	if [[ -f $1 && ${1##*.} == 'mkv' ]]; then
		files+=("$(readlink -f "$1")")
	else
		usage 1
	fi

	shift
done

# The loop below goes through the list of Matroska files, checks if they
# contain subtitles, and if so extracts them.
for (( i = 0; i < ${#files[@]}; i++ )); do
	if[fn]="${files[${i}]}"
	if[bn]=$(basename "${if[fn]}")
	if[bn_lc]="${if[bn],,}"
	of[fn]="${if[fn]%.*}-${RANDOM}.mkv"

	mapfile -t if_subs < <(mkvinfo "${if[fn]}" 2>&- | grep 'Track type: subtitles')

	if [[ ${#if_subs[@]} -eq 0 ]]; then
		usage 2
	fi

	mkvmerge --title "" -o "${of[fn]}" --no-video --no-audio --no-chapters "${if[fn]}" || exit "$?"
done
