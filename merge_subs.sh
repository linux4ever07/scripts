#!/bin/bash

# This script is meant to mux extra subtitles into an MKV file, and
# also set the default subtitle. It asks the user to select the default
# subtitle from a menu.

if=$(readlink -f "$1")
if_bn=$(basename "$if")
if_bn_lc="${if_bn,,}"
session="${RANDOM}-${RANDOM}"
of="${if%.[^.]*}-${session}.mkv"

declare sub_tracks_total_n srt_tracks_total_n
declare -a mkvinfo_tracks
declare -A tracks sub_tracks srt_tracks

regex_start='^\|\+ Tracks$'
regex_stop='^\|\+ '
regex_line='^\| +\+ '
regex_track="${regex_line}Track$"
regex_num="${regex_line}Track number: [0-9]+ \(track ID for mkvmerge & mkvextract: ([0-9]+)\)$"
regex_sub="${regex_line}Track type: subtitles$"
regex_lang="${regex_line}Language( \(.*\)){0,1}: (.*)$"
regex_name="${regex_line}Name: (.*)$"

regex_lang_arg='^[[:alpha:]]{3}$'

declare offset

usage () {
	cat <<USAGE

Usage: $(basename "$0") [mkv] [srt] [args] [...]

	Optional arguments:

[srt]
	File name of subtitle to be added (needs to be specified before the
	other arguments).

-lang [code]
	Three-letter language code for added subtitle.

-name [...]
	Name for added subtitle.

USAGE
	exit
}

if [[ ! -f $if || ${if_bn_lc##*.} != 'mkv' ]]; then
	usage
fi

# The loop below handles the arguments to the script.
shift

srt_tracks_n=0

while [[ -n $@ ]]; do
	case "$1" in
		'-lang')
			shift

			if [[ $1 =~ $regex_lang_arg ]]; then
				srt_tracks[${srt_tracks_n},lang]="${1,,}"
			else
				usage
			fi

			shift
		;;
		'-name')
			shift

			srt_tracks[${srt_tracks_n},name]="$1"

			shift
		;;
		*)
			if [[ -f $1 ]]; then
				srt_tracks_n=$(( srt_tracks_n + 1 ))

				srt_tracks[${srt_tracks_n},file]=$(readlink -f "$1")

				shift
			else
				usage
			fi
		;;
	esac
done

srt_tracks_n=$(( srt_tracks_n + 1 ))
srt_tracks_total_n="$srt_tracks_n"

command -v mkvinfo 1>&- 2>&-

if [[ $? -ne 0 ]]; then
	printf '\nThis script needs %s installed!\n\n' 'mkvtoolnix'
	exit
fi

mapfile -t mkvinfo_lines < <(mkvinfo "$if" 2>&-)

# Singles out the part that lists the tracks, and ignores the rest of
# the output from 'mkvinfo'.
switch=0

for (( i = 0; i < ${#mkvinfo_lines[@]}; i++ )); do
	line="${mkvinfo_lines[${i}]}"

	if [[ $line =~ $regex_start ]]; then
		switch=1
		continue
	fi

	if [[ $switch -eq 1 ]]; then
		if [[ $line =~ $regex_stop ]]; then
			switch=0
			break
		fi

		mkvinfo_tracks+=("$line")
	fi
done

# Gets all tracks from Matroska file.
tracks_n=0

for (( i = 0; i < ${#mkvinfo_tracks[@]}; i++ )); do
	line="${mkvinfo_tracks[${i}]}"

	if [[ $line =~ $regex_track ]]; then
		tracks_n=$(( tracks_n + 1 ))

		tracks[${tracks_n},sub]=0
	fi

	if [[ $line =~ $regex_num ]]; then
		tracks[${tracks_n},num]="${BASH_REMATCH[1]}"
	fi

	if [[ $line =~ $regex_sub ]]; then
		tracks[${tracks_n},sub]=1
	fi

	if [[ $line =~ $regex_lang ]]; then
		tracks[${tracks_n},lang]="${BASH_REMATCH[2]}"
	fi

	if [[ $line =~ $regex_name ]]; then
		tracks[${tracks_n},name]="${BASH_REMATCH[1]}"
	fi
done

tracks_n=$(( tracks_n + 1 ))

sub_tracks_n=0

# Gets all subtitle tracks specifically.
for (( i = 1; i < tracks_n; i++ )); do
	if [[ ${tracks[${i},sub]} -eq 1 ]]; then
		sub_tracks_n=$(( sub_tracks_n + 1 ))
	else
		continue
	fi

	if [[ -n ${tracks[${i},num]} ]]; then
		sub_tracks[${sub_tracks_n},num]="${tracks[${i},num]}"
	fi

	if [[ -n ${tracks[${i},lang]} ]]; then
		sub_tracks[${sub_tracks_n},lang]="${tracks[${i},lang]}"
	fi

	if [[ -n ${tracks[${i},name]} ]]; then
		sub_tracks[${sub_tracks_n},name]="${tracks[${i},name]}"
	fi
done

sub_tracks_total_n=$(( sub_tracks_n + 1 ))

# Adds all the SRT files that were given as arguments to the script, to
# the 'sub_tracks' hash.
for (( i = 1; i < srt_tracks_total_n; i++ )); do
	if [[ -n ${srt_tracks[${i},file]} ]]; then
		sub_tracks_n=$(( sub_tracks_n + 1 ))

		sub_tracks[${sub_tracks_n},file]="${srt_tracks[${i},file]}"
	fi

	if [[ -n ${srt_tracks[${i},lang]} ]]; then
		sub_tracks[${sub_tracks_n},lang]="${srt_tracks[${i},lang]}"
	fi

	if [[ -n ${srt_tracks[${i},name]} ]]; then
		sub_tracks[${sub_tracks_n},name]="${srt_tracks[${i},name]}"
	fi
done

sub_tracks_n=$(( sub_tracks_n + 1 ))

printf '\n%s\n\n' "$if"

# Prints all the subtitle tracks, and asks the user to choose the
# default track, saves that choice in the $default variable.
printf '%s\n\n' 'Choose the default track:'

for (( i = 1; i < sub_tracks_total_n; i++ )); do
	lang_tmp="${sub_tracks[${i},lang]}"
	name_tmp="${sub_tracks[${i},name]}"

	printf '%s)\n' "$i"
	printf '  language: %s\n' "$lang_tmp"
	printf '  name: %s\n' "$name_tmp"
done

for (( i = sub_tracks_total_n; i < sub_tracks_n; i++ )); do
	file_tmp="${sub_tracks[${i},file]}"
	lang_tmp="${sub_tracks[${i},lang]}"
	name_tmp="${sub_tracks[${i},name]}"

	printf '%s)\n' "$i"
	printf '  file: %s\n' "$file_tmp"
	printf '  language: %s\n' "$lang_tmp"
	printf '  name: %s\n' "$name_tmp"
done

printf '\n%s' '>'
read default

until [[ $default -lt $sub_tracks_n ]]; do
	printf '\n%s' '>'
	read default
done

printf '\nDefault subtitle track: %s\n' "$default"

if [[ -n ${sub_tracks[${default},num]} ]]; then
	printf '(Track ID: %s)\n' "${sub_tracks[${default},num]}"
fi

# Puts together the mkvmerge command. The loop below deals with
# subtitles that are in the Matroska file.
for (( i = 1; i < sub_tracks_total_n; i++ )); do
	num_tmp="${sub_tracks[${i},num]}"

	if [[ $i -eq $default ]]; then
		args1+=("--default-track-flag ${num_tmp}:1")
	else
		args1+=("--default-track-flag ${num_tmp}:0")
	fi
done

# This loop deals with the SRT subtitles given as arguments to the
# script.
for (( i = sub_tracks_total_n; i < sub_tracks_n; i++ )); do
	file_tmp="${sub_tracks[${i},file]}"
	lang_tmp="${sub_tracks[${i},lang]}"
	name_tmp="${sub_tracks[${i},name]}"

	if [[ -n $lang_tmp ]]; then
		args2+=('--language' 0:\""${lang_tmp}"\")
	fi

	if [[ -n $name_tmp ]]; then
		args2+=('--track-name' 0:\""${name_tmp}"\")
	fi

	if [[ $i -eq $default ]]; then
		args2+=('--default-track-flag 0:1')
	else
		args2+=('--default-track-flag 0:0')
	fi

	if [[ -n $file_tmp ]]; then
		args2+=(\""${file_tmp}"\")
	fi
done

eval mkvmerge -o \""$of"\" "${args1[@]}" \""$if"\" "${args2[@]}"

printf '\n'

string="mkvmerge -o \"$of\" ${args1[@]} \"$if\" ${args2[@]}"
printf '%s\n\n' "$string"
