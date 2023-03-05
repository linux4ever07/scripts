#!/bin/bash

# This script is meant to get the length of all individual tracks in a
# CUE sheet.

if=$(readlink -f "$1")
if_bn=$(basename "$if")
if_bn_lc="${if_bn,,}"

if_name="${if_bn_lc%.*}"
if_dn=$(dirname "$if")
cue="$if"

# Creates a function called 'usage', which will print usage and quit.
usage () {
	printf '\n%s\n\n' "Usage: $(basename "$0") [cue]"
	exit
}

# If input is not a real file, or it has the wrong extension, print
# usage and quit.
if [[ ! -f $if || ${if_bn_lc##*.} != 'cue' ]]; then
	usage
fi

declare -a format
declare -A regex

format[0]='^[0-9]+$'
format[1]='([0-9]{2}):([0-9]{2}):([0-9]{2})'
format[2]='[0-9]{2}:[0-9]{2}:[0-9]{2}'
format[3]='^(FILE) (.*) (.*)$'
format[4]='^(TRACK) ([0-9]{2,}) (.*)$'
format[5]="^(PREGAP) (${format[2]})$"
format[6]="^(INDEX) ([0-9]{2,}) (${format[2]})$"
format[7]="^(POSTGAP) (${format[2]})$"

regex[blank]='^[[:blank:]]*(.*)[[:blank:]]*$'
regex[path]='^(.*[\\\/])'

regex[data]='^MODE([0-9]+)/([0-9]+)$'
regex[audio]='^AUDIO$'

declare -a tracks_file tracks_type tracks_sector frames
declare -A if_cue

# Creates a function called 'time_convert', which converts track
# timestamps back and forth between the time (mm:ss:ff) format and
# frames / sectors.
time_convert () {
	time="$1"

	m=0
	s=0
	f=0

# If argument is in the mm:ss:ff format...
	if [[ $time =~ ${format[1]} ]]; then
		m="${BASH_REMATCH[1]#0}"
		s="${BASH_REMATCH[2]#0}"
		f="${BASH_REMATCH[3]#0}"

# Converting minutes and seconds to frames, and adding all the numbers
# together.
		m=$(( m * 60 * 75 ))
		s=$(( s * 75 ))

		time=$(( m + s + f ))

# If argument is in the frame format...
	elif [[ $time =~ ${format[0]} ]]; then
		f="$time"

		s=$(( f / 75 ))
		m=$(( s / 60 ))

		f=$(( f % 75 ))
		s=$(( s % 60 ))

		time=$(printf '%02d:%02d:%02d' "$m" "$s" "$f")
	fi

	printf '%s' "$time"
}

# Creates a function called 'read_cue', which will read the source CUE
# sheet, add full path to filenames listed in the CUE sheet, and create
# a new temporary CUE sheet in /dev/shm based on this.
read_cue () {
	declare file_n track_n
	declare -a files not_found wrong_format wrong_mode lines

	declare -a error_types
	declare -A error_msgs

	file_n=0
	track_n=0

	error_types=('not_found' 'wrong_format' 'wrong_mode')
	error_msgs[not_found]='The files below were not found:'
	error_msgs[wrong_format]='The files below have the wrong format:'
	error_msgs[wrong_mode]='The tracks below have an unrecognized mode:'

# Creates a function called 'handle_command', which will process each
# line in the CUE sheet and store all the relevant information in the
# 'if_cue' hash.
	handle_command () {
# If line is a FILE command...
		if [[ $1 =~ ${format[3]} ]]; then
			match=("${BASH_REMATCH[@]:1}")

# Strips quotes, and path that may be present in the CUE sheet, and adds
# full path to the basename.
			fn=$(tr -d '"' <<<"${match[1]}" | sed -E "s/${regex[path]}//")
			fn="${if_dn}/${fn}"

# If file can't be found, or format isn't binary, then it's useless even
# trying to process this CUE sheet.
			if [[ ! -f $fn ]]; then
				not_found+=("$fn")
			fi

			if [[ ${match[2]} != 'BINARY' ]]; then
				wrong_format+=("$fn")
			fi

			files+=("$fn")

			string="${match[0]} \"${fn}\" ${match[2]}"

			file_n=$(( file_n + 1 ))

			if_cue["${file_n},filename"]="$fn"
			if_cue["${file_n},file_format"]="${match[2]}"
		fi

# If line is a TRACK command...
		if [[ $1 =~ ${format[4]} ]]; then
			match=("${BASH_REMATCH[@]:1}")

			track_n="${match[1]#0}"

# Saves the file number associated with this track.
			tracks_file["${track_n}"]="$file_n"

# Figures out if this track is data or audio, and saves the sector size.
# Typical sector size is 2048 bytes for data CDs, and 2352 for audio.
			if [[ ${match[2]} =~ ${regex[data]} ]]; then
				tracks_type["${track_n}"]='data'
				tracks_sector["${track_n}"]="${BASH_REMATCH[2]}"
			fi

			if [[ ${match[2]} =~ ${regex[audio]} ]]; then
				tracks_type["${track_n}"]='audio'
				tracks_sector["${track_n}"]=2352
			fi

# If the track mode was not recognized, then it's useless even trying to
# process this CUE sheet.
			if [[ -z ${tracks_sector[${track_n}]} ]]; then
				wrong_mode+=("$track_n")
			fi

			string="$1"

			if_cue["${track_n},track_number"]="${match[1]}"
			if_cue["${track_n},track_mode"]="${match[2]}"
		fi

# If line is a PREGAP command...
		if [[ $1 =~ ${format[5]} ]]; then
			match=("${BASH_REMATCH[@]:1}")

			string="$1"

			frames_tmp=$(time_convert "${match[1]}")
			if_cue["${track_n},pregap"]="$frames_tmp"
		fi

# If line is an INDEX command...
		if [[ $1 =~ ${format[6]} ]]; then
			match=("${BASH_REMATCH[@]:1}")

			index_n="${match[1]#0}"

			string="$1"

			frames_tmp=$(time_convert "${match[2]}")
			if_cue["${track_n},index,${index_n}"]="$frames_tmp"
		fi

# If line is a POSTGAP command...
		if [[ $1 =~ ${format[7]} ]]; then
			match=("${BASH_REMATCH[@]:1}")

			string="$1"

			frames_tmp=$(time_convert "${match[1]}")
			if_cue["${track_n},postgap"]="$frames_tmp"
		fi
	}

# Reads the source CUE sheet and processes the lines.
	mapfile -t lines < <(tr -d '\r' <"$cue" | sed -E "s/${regex[blank]}/\1/")

	for (( i = 0; i < ${#lines[@]}; i++ )); do
		line="${lines[${i}]}"
		handle_command "$line"
	done

# If errors were found, print them and quit.
	for error in "${error_types[@]}"; do
		declare elements msg_ref list_ref

		elements=0

		case "$error" in
			'not_found')
				elements="${#not_found[@]}"
			;;
			'wrong_format')
				elements="${#wrong_format[@]}"
			;;
			'wrong_mode')
				elements="${#wrong_mode[@]}"
			;;
		esac

		if [[ $elements -eq 0 ]]; then
			continue
		fi

		msg_ref="error_msgs[${error}]"
		list_ref="${error}[@]"

		printf '\n%s\n\n' "${!msg_ref}"
		printf '%s\n' "${!list_ref}"
		printf '\n'

		exit
	done
}

# Creates a function called 'get_frames', which will get the length of
# a track in the BIN file.
get_frames () {
	this="$1"
	next=$(( this + 1 ))

	declare file_this_ref file_next_ref sector_ref bin_ref
	declare index_this_ref index_next_ref frames_tmp size

	file_this_ref="tracks_file[${this}]"
	file_next_ref="tracks_file[${next}]"

	sector_ref="tracks_sector[${this}]"
	bin_ref="if_cue[${!file_this_ref},filename]"

	index_this_ref="if_cue[${this},index,0]"
	index_next_ref="if_cue[${next},index,0]"

	if [[ -z ${!index_this_ref} ]]; then
		index_this_ref="if_cue[${this},index,1]"
	fi

	if [[ -z ${!index_next_ref} ]]; then
		index_next_ref="if_cue[${next},index,1]"
	fi

	if [[ ${!file_this_ref} -ne ${!file_next_ref} ]]; then
		size=$(stat -c '%s' "${!bin_ref}")
		size=$(( size / ${!sector_ref} ))

		frames_tmp=$(( size - ${!index_this_ref} ))
	else
		frames_tmp=$(( ${!index_next_ref} - ${!index_this_ref} ))
	fi

	frames["${this}"]="$frames_tmp"
}

# Creates a function called 'loop_set', which will get the length of all
# tracks in the BIN file (except the last one).
loop_set () {
	declare track_n file_n

	for (( i = 0; i < ${#tracks_file[@]}; i++ )); do
		track_n=$(( i + 1 ))

		get_frames "$track_n"
	done
}

read_cue
loop_set

last=$(( ${#frames[@]} + 1 ))

printf '\n'

for (( i = 1; i < last; i++ )); do
	printf 'Track %02d) %s , frames: %s\n' "$i" "$(time_convert "${frames[${i}]}")" "${frames[${i}]}"
done

printf '\n'
