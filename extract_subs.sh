#!/bin/bash

# This script is meant to extract all the subtitles from an MKV
# (Matroska) file. The output filename is the same as the input
# filename, only a random number is added to the name.

usage () {
	declare -a msg

	msg[0]="You need mkvtoolnix installed to run this script."
	msg[1]="Usage: $(basename "$0") [mkv]"
	msg[2]="There are no subtitles in: ${if_bn}"
	printf '\n%s\n\n' "${msg[${1}]}"
	exit
}

declare -a cmd if_subs
declare -A if of

if[fn]=$(readlink -f "$1")
if[bn]=$(basename "${if[fn]}")
if[bn_lc]="${if[bn],,}"
of[fn]="${if[fn]%.*}-${RANDOM}.mkv"

mapfile -t cmd < <(command -v mkvinfo mkvmerge)

if [[ ${#cmd[@]} -ne 2 ]]; then
	usage 0
fi

if [[ ! -f ${if[fn]} || ${if[bn_lc]##*.} != 'mkv' ]]; then
	usage 1
fi

mapfile -t if_subs < <(mkvinfo "${if[fn]}" 2>&- | grep 'Track type: subtitles')

if [[ ${#if_subs[@]} -eq 0 ]]; then
	usage 2
fi

mkvmerge --title "" -o "${of[fn]}" --no-video --no-audio --no-chapters "${if[fn]}"

exit "$?"
