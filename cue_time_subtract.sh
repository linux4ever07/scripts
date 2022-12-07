#!/bin/bash

# This script is meant to get the length of all individual tracks in a
# CUE sheet.

if=$(readlink -f "$1")
if_bn=$(basename "$if")
if_bn_lc="${if_bn,,}"

if_name="${if_bn_lc%.[^.]*}"
if_dn=$(dirname "$if")
cue="$if"

# Creates a function called 'usage', which will print usage and quit.
usage () {
	printf '\n%s\n\n' "Usage: $(basename "$0") [cue]"
	exit
}

# If $if is not a real file, or it has the wrong extension, print usage
# and quit.
if [[ ! -f $if || ${if_bn_lc##*.} != 'cue' ]]; then
	usage
fi

bin=$(find "$if_dn" -maxdepth 1 -type f -iname "${if_name}.bin" 2>&- | head -n 1)

declare -a format

format[0]='^[0-9]+$'
format[1]='([0-9]{2}):([0-9]{2}):([0-9]{2})'
format[2]='[0-9]{2}:[0-9]{2}:[0-9]{2}'
format[3]='^(FILE) (.*) (.*)$'
format[4]='^(TRACK) ([0-9]{2,}) (.*)$'
format[5]="^(PREGAP) (${format[2]})$"
format[6]="^(INDEX) ([0-9]{2,}) (${format[2]})$"
format[7]="^(POSTGAP) (${format[2]})$"

regex_blank='^[[:blank:]]*(.*)[[:blank:]]*$'
regex_path='^(.*[\/])'

declare -A cue_lines
declare -a frames

# Creates a function called 'read_cue', which will read the input CUE
# sheet, add full path to filenames listed in the CUE sheet, and create
# a new temporary CUE sheet in /dev/shm based on this.
read_cue () {
	declare -a files not_found

	track_n=0

	handle_command () {
# If line is a file command...
		if [[ $1 =~ ${format[3]} ]]; then
			match=("${BASH_REMATCH[@]:1}")
			track_n=$(( track_n + 1 ))
			fn=$(tr -d '"' <<<"${match[1]}" | sed -E "s/${regex_path}//")
			fn="${if_dn}/${fn}"

			if [[ ! -f $fn ]]; then
				not_found+=("$fn")
			fi

			if [[ $track_n -eq 1 ]]; then
				if [[ -z $bin && -f $fn ]]; then
					bin="$fn"
				fi
			fi

			files+=("$fn")

			string="${match[0]} \"${fn}\" ${match[2]}"

			cue_lines["${track_n},filename"]="$fn"
			cue_lines["${track_n},file_format"]="${match[2]}"
		fi

# If line is a track command...
		if [[ $1 =~ ${format[4]} ]]; then
			match=("${BASH_REMATCH[@]:1}")
			track_n="${match[1]#0}"

			string="$1"

			cue_lines["${track_n},track_number"]="${match[1]}"
			cue_lines["${track_n},track_mode"]="${match[2]}"
		fi

# If line is a pregap command...
		if [[ $1 =~ ${format[5]} ]]; then
			match=("${BASH_REMATCH[@]:1}")

			string="$1"

			cue_lines["${track_n},pregap"]="${match[1]}"
		fi

# If line is an index command...
		if [[ $1 =~ ${format[6]} ]]; then
			match=("${BASH_REMATCH[@]:1}")
			index_n="${match[1]#0}"

			string="$1"

			cue_lines["${track_n},index,${index_n}"]="${match[2]}"
		fi

# If line is a postgap command...
		if [[ $1 =~ ${format[7]} ]]; then
			match=("${BASH_REMATCH[@]:1}")

			string="$1"

			cue_lines["${track_n},postgap"]="${match[1]}"
		fi
	}

	mapfile -t cue_lines_if < <(tr -d '\r' <"$cue" | sed -E "s/${regex_blank}/\1/")

	for (( i = 0; i < ${#cue_lines_if[@]}; i++ )); do
		line="${cue_lines_if[${i}]}"
		handle_command "$line"
	done

	if [[ ${#files[@]} -gt 1 ]]; then
		cat <<MERGE

This CUE sheet contains multiple FILE commands!

MERGE

		exit
	fi

	if [[ ${#not_found[@]} -gt 0 ]]; then
		printf '\n%s\n\n' 'The files below were not found:'

		printf '%s\n' "${not_found[@]}"

		printf '\n'
	fi
}

# Creates a function called 'get_frames', which will get the position of
# a track in the BIN file.
get_frames () {
	track_n="$1"
	declare index_0_ref index_1_ref index_ref frames_tmp

	index_0_ref="cue_lines[${track_n},index,0]"
	index_1_ref="cue_lines[${track_n},index,1]"

	if [[ -n ${!index_0_ref} ]]; then
		index_ref="$index_0_ref"
	else
		index_ref="$index_1_ref"
	fi

	if [[ -n ${!index_ref} ]]; then
		frames_tmp=$(time_convert "${!index_ref}")
		printf '%s' "$frames_tmp"
	fi
}

# Creates a function called 'set_frames', which will get the length of
# all tracks in the BIN file (except the last one).
set_frames () {
	i=0
	declare frames_this frames_next size frames_total

	while true; do
		i=$(( i + 1 ))
		j=$(( i + 1 ))
		frames_this=$(get_frames "$i")
		frames_next=$(get_frames "$j")

		if [[ -n $frames_next ]]; then
			frames["${i}"]=$(( frames_next - frames_this ))
		else
			if [[ -n $bin ]]; then
				size=$(stat -c '%s' "$bin")
				frames_total=$(( size / 2352 ))
				frames["${i}"]=$(( frames_total - frames_this ))
			else
				frames["${i}"]=0
			fi

			break
		fi
	done
}

# Creates a function called 'time_convert', which converts track length
# back and forth between the time (mm:ss:ff) format and frames /
# sectors.
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

# While $f (frames) is equal to (or greater than) 75, clear the $f
# variable and add 1 to the $s (seconds) variable.
		while [[ $f -ge 75 ]]; do
			s=$(( s + 1 ))
			f=$(( f - 75 ))
		done

# While $s (seconds) is equal to (or greater than) 60, clear the $s
# variable and add 1 to the $m (minutes) variable.
		while [[ $s -ge 60 ]]; do
			m=$(( m + 1 ))
			s=$(( s - 60 ))
		done

		time=$(printf '%02d:%02d:%02d' "$m" "$s" "$f")
	fi

	printf '%s' "$time"
}

read_cue
set_frames

last=$(( ${#frames[@]} + 1 ))

printf '\n'

for (( i = 1; i < last; i++ )); do
	printf 'Track %02d) %s , frames: %s\n' "$i" "$(time_convert "${frames[${i}]}")" "${frames[${i}]}"
done

printf '\n'
