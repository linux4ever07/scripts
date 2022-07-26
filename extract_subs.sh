#!/bin/bash
# This script is meant to extract all the subtitles from a Matroska
# (.mkv) file. The output filename is the same as the input filename,
# only a random number is added to the name.

usage () {
	msg[0]="You need mkvtoolnix installed to run this script."
	msg[1]="Usage: $(basename "$0") [MKV]"
	msg[2]="There are no subtitles in:\n${if}"
	printf '%s\n\n' "${msg[${1}]}"
	exit
}

cmd=$(command -v mkvmerge 2>&-)
if=$(readlink -f "$1" 2>&-)
of_tmp="${if%.mkv}"
of="${of_tmp}-${RANDOM}.mkv"

if [[ -z $cmd ]]; then
	usage 0
fi

if [[ ! -f $if ]]; then
	usage 1
fi

mapfile -t if_subs < <(mkvinfo "${if}" 2>&- | grep 'Track type: subtitles')

if [[ -z ${if_subs[@]} ]]; then
	usage 2
fi

mkvmerge --title "" -o "${of}" --no-video --no-audio --no-chapters "${if}"

exit "$?"
