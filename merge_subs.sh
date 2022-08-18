#!/bin/bash

# This script is meant to mux extra subtitles into an MKV file, and
# also set the default subtitle.

if=$(readlink -f "$1")
if_bn=$(basename "$if")
if_bn_lc="${if_bn,,}"
session="${RANDOM}-${RANDOM}"
of="${if%.[^.]*}-${session}.mkv"

declare -A srt_file srt_lang srt_name
declare -a sub_tracks args1 args2

regex_track='^.*Track number: [0-9]+ \(track ID for mkvmerge & mkvextract: ([0-9]+)\)'
regex_num='^[0-9]$'
regex_sub='^.*Track type: subtitles'

usage () {
	cat <<USAGE

Usage: $(basename "$0") [mkv] [default track #] [...]

	Optional arguments:

-lang [code]
	Language for added subtitle.

-name [...]
	Name for added subtitle (needs to be specified after -lang, if at
	all).

[srt]
	File name of subtitle to be added (needs to be specified after above
	arguments).

USAGE
	exit
}

if [[ ! -f $if || ${if_bn_lc##*.} != 'mkv' ]]; then
	usage
fi

shift

if [[ ! $1 =~ $regex_num ]]; then
	usage
fi

default="$1"

# The loop below handles the arguments to the script.
shift

n=0

while [[ -n $@ ]]; do
	case "$1" in
		'-lang')
			shift

			lang_regex='^[[:alpha:]]{3}$'
			name_regex='^-name$'

			if [[ ! $1 =~ $lang_regex ]]; then
				usage
			else
				srt_lang[${n}]="${1,,}"
			fi

			shift

			if [[ $1 =~ $name_regex ]]; then
				shift

				srt_name[${n}]="$1"

				shift
			elif [[ -f $1 ]]; then
				srt_file[${n}]="$1"

				shift
			fi

			if [[ -f $1 && -z ${srt_file[${n}]} ]]; then
				srt_file[${n}]="$1"

				shift
			fi

			n=$(( n + 1 ))
		;;
		*)
			usage
		;;
	esac
done

for (( i = 0; i < n; i++ )); do
	if [[ -n ${srt_lang[${i}]} ]]; then
		args2+=("--language" 0:\""${srt_lang[${i}]}"\")
	fi
	if [[ -n ${srt_name[${i}]} ]]; then
		args2+=("--track-name" 0:\""${srt_name[${i}]}"\")
	fi
	if [[ -n ${srt_file[${i}]} ]]; then
		args2+=("--default-track-flag 0:0" \""${srt_file[${i}]}"\")
	fi
done

command -v mkvinfo 1>&- 2>&- || exit

mapfile -t mkv_info_list < <(mkvinfo "$if" 2>&-)

for (( i = 0; i < ${#mkv_info_list[@]}; i++ )); do
	line="${mkv_info_list[${i}]}"

	if [[ $line =~ $regex_track ]]; then
		track="${BASH_REMATCH[1]}"
		next=$(( i + 1 ))
		line_next="${mkv_info_list[${next}]}"

		until [[ $line_next =~ $regex_sub ]]; do
			next=$(( next + 1 ))
			line_next="${mkv_info_list[${next}]}"

			if [[ $line_next =~ $regex_track ]]; then
				break
			elif [[ $next -ge ${#mkv_info_list[@]} ]]; then
				break
			fi
		done

		if [[ $line_next =~ $regex_sub ]]; then
			sub_tracks+=("$track")
		fi
	fi
done

for (( i = 0; i < ${#sub_tracks[@]}; i++ )); do
	track="${sub_tracks[${i}]}"

	if [[ $track -eq $default ]]; then
		continue
	fi

	args1+=("--default-track-flag ${track}:0")
done

eval mkvmerge -o \""$of"\" --default-track-flag "${default}":1 "${args1[@]}" \""$if"\" "${args2[@]}"

printf '\n'

eval echo \"mkvmerge -o \\\""$of"\\\" --default-track-flag "${default}":1 "${args1[@]}" \\\""$if"\\\" "${args2[@]}"\"

printf '\n'
