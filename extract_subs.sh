#!/bin/bash

# This script is meant to extract all the subtitles from MKV (Matroska)
# files. The output file name is the same as the input file name, only a
# random number is added to the name.

declare -a cmd files input_subs
declare -A input output

# Creates a function called 'usage', which will print a message and then
# quit.
usage () {
	declare -a msg

	msg[0]="This script needs mkvtoolnix installed!"
	msg[1]="Usage: $(basename "$0") [mkv]"
	msg[2]="There are no subtitles in: ${input[bn]}"

	printf '\n%s\n\n' "${msg[${1}]}"

	exit
}

mapfile -t cmd < <(command -v mkvinfo mkvmerge)

if [[ ${#cmd[@]} -ne 2 ]]; then
	usage 0
fi

# The loop below handles the arguments to the script.
while [[ $# -gt 0 ]]; do
	input[fn]=$(readlink -f "$1")
	input[ext]="${input[fn]##*.}"
	input[ext]="${input[ext],,}"

	shift

	if [[ ! -f ${input[fn]} || ${input[ext]} != 'mkv' ]]; then
		continue
	fi

	files+=("${input[fn]}")
done

if [[ ${#files[@]} -eq 0 ]]; then
	usage 1
fi

# The loop below goes through the list of Matroska files, checks if they
# contain subtitles, and if so extracts them.
for (( i = 0; i < ${#files[@]}; i++ )); do
	input[fn]="${files[${i}]}"
	input[bn]=$(basename "${input[fn]}")
	output[fn]="${input[fn]%.*}-${RANDOM}.mkv"

	mapfile -t input_subs < <(mkvinfo "${input[fn]}" 2>&- | grep 'Track type: subtitles')

	if [[ ${#input_subs[@]} -eq 0 ]]; then
		usage 2
	fi

	mkvmerge --title "" -o "${output[fn]}" --no-video --no-audio --no-chapters "${input[fn]}" || exit "$?"
done
