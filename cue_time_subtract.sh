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

declare -A regex
declare -a format sector

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

# 2048 bytes is normally the sector size for data CDs / tracks, and 2352
# bytes is the size of audio sectors.
sector=('2048' '2352')

declare -A if_cue
declare -a frames

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

# Creates a function called 'read_cue', which will read the source CUE
# sheet, add full path to filenames listed in the CUE sheet, and create
# a new temporary CUE sheet in /dev/shm based on this.
read_cue () {
	declare -a files not_found lines

	track_n=0

# Creates a function called 'handle_command', which will process each
# line in the CUE sheet and store all the relevant information in the
# 'if_cue' hash.
	handle_command () {
# If line is a FILE command...
		if [[ $1 =~ ${format[3]} ]]; then
			match=("${BASH_REMATCH[@]:1}")
			track_n=$(( track_n + 1 ))
			fn=$(tr -d '"' <<<"${match[1]}" | sed -E "s/${regex[path]}//")
			fn="${if_dn}/${fn}"

			if [[ ! -f $fn ]]; then
				not_found+=("$fn")
			fi

			if [[ $track_n -eq 1 && -z $bin && -f $fn ]]; then
				bin="$fn"
			fi

			files+=("$fn")

			string="${match[0]} \"${fn}\" ${match[2]}"

			if_cue["${track_n},filename"]="$fn"
			if_cue["${track_n},file_format"]="${match[2]}"
		fi

# If line is a TRACK command...
		if [[ $1 =~ ${format[4]} ]]; then
			match=("${BASH_REMATCH[@]:1}")
			track_n="${match[1]#0}"

			string="$1"

			if_cue["${track_n},track_number"]="${match[1]}"
			if_cue["${track_n},track_mode"]="${match[2]}"
		fi

# If line is a PREGAP command...
		if [[ $1 =~ ${format[5]} ]]; then
			match=("${BASH_REMATCH[@]:1}")

			string="$1"

			time_tmp=$(time_convert "${match[1]}")
			if_cue["${track_n},pregap"]="$time_tmp"
		fi

# If line is an INDEX command...
		if [[ $1 =~ ${format[6]} ]]; then
			match=("${BASH_REMATCH[@]:1}")
			index_n="${match[1]#0}"

			string="$1"

			time_tmp=$(time_convert "${match[2]}")
			if_cue["${track_n},index,${index_n}"]="$time_tmp"
		fi

# If line is a POSTGAP command...
		if [[ $1 =~ ${format[7]} ]]; then
			match=("${BASH_REMATCH[@]:1}")

			string="$1"

			time_tmp=$(time_convert "${match[1]}")
			if_cue["${track_n},postgap"]="$time_tmp"
		fi
	}

# Reads the source CUE sheet and processes the lines.
	mapfile -t lines < <(tr -d '\r' <"$cue" | sed -E "s/${regex[blank]}/\1/")

	for (( i = 0; i < ${#lines[@]}; i++ )); do
		line="${lines[${i}]}"
		handle_command "$line"
	done

# If there's multiple FILE commands in the CUE sheet, quit.
	if [[ ${#files[@]} -gt 1 ]]; then
		cat <<MERGE

This CUE sheet contains multiple FILE commands!

MERGE

		exit
	fi

# Lists file names that are not real files.
	if [[ ${#not_found[@]} -gt 0 ]]; then
		printf '\n%s\n\n' 'The files below were not found:'

		printf '%s\n' "${not_found[@]}"

		printf '\n'
	fi
}

# Creates a function called 'get_frames', which will get the length of
# a track in the BIN file, subtracting pregap if it exists as part of
# the INDEX commands.
get_frames () {
	this="$1"
	next=$(( this + 1 ))

	declare index_this_ref index_next_ref frames_tmp size

	index_this_ref="if_cue[${this},index,1]"
	index_next_ref="if_cue[${next},index,0]"

	if [[ -z ${!index_next_ref} ]]; then
		index_next_ref="if_cue[${next},index,1]"
	fi

	frames_tmp=0

	if [[ -z ${!index_next_ref} ]]; then
		if [[ -n $bin ]]; then
			size=$(stat -c '%s' "$bin")
			size=$(( size / ${sector[1]} ))

			frames_tmp=$(( size - ${!index_this_ref} ))
		fi
	else
		frames_tmp=$(( ${!index_next_ref} - ${!index_this_ref} ))
	fi

	frames["${this}"]="$frames_tmp"
}

# Creates a function called 'loop_set', which will get the length of all
# tracks in the BIN file (except the last one).
loop_set () {
	declare track_ref

	i=0

	while [[ 1 ]]; do
		i=$(( i + 1 ))
		track_ref="if_cue[${i},track_number]"

		if [[ -n ${!track_ref} ]]; then
			get_frames "$i"
		else
			break
		fi
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
