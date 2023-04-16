#!/bin/bash

# This script is meant to get the length of all individual tracks in a
# CUE sheet.

if=$(readlink -f "$1")
if_dn=$(dirname "$if")
if_bn=$(basename "$if")
if_bn_lc="${if_bn,,}"

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
format[1]='^([0-9]{2}):([0-9]{2}):([0-9]{2})$'
format[2]='[0-9]{2}:[0-9]{2}:[0-9]{2}'
format[3]='^(FILE) (.*) (.*)$'
format[4]='^(TRACK) ([0-9]{2,}) (.*)$'
format[5]="^(PREGAP) (${format[2]})$"
format[6]="^(INDEX) ([0-9]{2,}) (${format[2]})$"
format[7]="^(POSTGAP) (${format[2]})$"

regex[blank]='^[[:blank:]]*(.*)[[:blank:]]*$'
regex[path]='^(.*[\\\/])'

regex[data]='^MODE([0-9])\/([0-9]{4})$'
regex[audio]='^AUDIO$'

declare -a tracks_file tracks_type tracks_sector tracks_start tracks_length tracks_total
declare -A if_cue gaps

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
# sheet, get all the relevant information from it and store that in
# variables. It will also add full path to file names listed in the CUE
# sheet.
read_cue () {
	declare line file_n track_n
	declare -a lines files not_found wrong_format wrong_mode

	declare -a error_types
	declare -A error_msgs

	file_n=0
	track_n=0

	error_types=('not_found' 'wrong_format' 'wrong_mode')
	error_msgs[no_files]='No files were found in CUE sheet!'
	error_msgs[not_found]='The files below were not found:'
	error_msgs[wrong_format]='The files below have the wrong format:'
	error_msgs[wrong_mode]='The tracks below have an unrecognized mode:'

# Creates a function called 'handle_command', which will process each
# line in the CUE sheet and store all the relevant information in the
# 'if_cue' hash.
	handle_command () {
# If line is a FILE command...
		if [[ $line =~ ${format[3]} ]]; then
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

			(( file_n += 1 ))

			if_cue["${file_n},filename"]="$fn"
			if_cue["${file_n},file_format"]="${match[2]}"

			return
		fi

# If line is a TRACK command...
		if [[ $line =~ ${format[4]} ]]; then
			match=("${BASH_REMATCH[@]:1}")

			track_n="${match[1]#0}"

# Saves the file number associated with this track.
			tracks_file["${track_n}"]="$file_n"

# Saves the current track number (and in effect, every track number) in
# an array so the exact track numbers can be referenced later.
			tracks_total+=("$track_n")

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
			if [[ -z ${tracks_type[${track_n}]} ]]; then
				wrong_mode+=("$track_n")
			fi

			if_cue["${track_n},track_number"]="${match[1]}"
			if_cue["${track_n},track_mode"]="${match[2]}"

			return
		fi

# If line is a PREGAP command...
		if [[ $line =~ ${format[5]} ]]; then
			match=("${BASH_REMATCH[@]:1}")

			frames=$(time_convert "${match[1]}")
			if_cue["${track_n},pregap"]="$frames"

			return
		fi

# If line is an INDEX command...
		if [[ $line =~ ${format[6]} ]]; then
			match=("${BASH_REMATCH[@]:1}")

			index_n="${match[1]#0}"

			frames=$(time_convert "${match[2]}")
			if_cue["${track_n},index,${index_n}"]="$frames"

			return
		fi

# If line is a POSTGAP command...
		if [[ $line =~ ${format[7]} ]]; then
			match=("${BASH_REMATCH[@]:1}")

			frames=$(time_convert "${match[1]}")
			if_cue["${track_n},postgap"]="$frames"

			return
		fi
	}

# Reads the source CUE sheet and processes the lines.
	mapfile -t lines < <(tr -d '\r' <"$if" | sed -E "s/${regex[blank]}/\1/")

	for (( i = 0; i < ${#lines[@]}; i++ )); do
		line="${lines[${i}]}"
		handle_command
	done

# If errors were found, print them and quit.
	if [[ ${#files[@]} -eq 0 ]]; then
		printf '\n%s\n\n' "${error_msgs[no_files]}"
		exit
	fi

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

# Creates a function called 'get_length', which will get the start
# position, and length, (in bytes) of all tracks in the respective BIN
# files.
get_length () {
	declare bytes_pregap bytes_track bytes_total frames
	declare pregap_this_ref pregap_next_ref
	declare index0_this_ref index1_this_ref index0_next_ref index1_next_ref
	declare file_n_this_ref file_n_next_ref file_ref
	declare sector_ref start_ref

	bytes_total=0

# Creates a function called 'get_size', which will get the track length
# by reading the size of the BIN file associated with this track. This
# function will also reset the 'bytes_total' variable to '0' (as the
# current track is last in the current BIN file).
	get_size () {
		declare size

		size=$(stat -c '%s' "${!file_ref}")

		bytes_track=$(( size - ${!start_ref} ))
		bytes_total=0

		tracks_length["${this}"]="$bytes_track"
	}

	for (( i = 0; i < ${#tracks_total[@]}; i++ )); do
		j=$(( i + 1 ))

		this="${tracks_total[${i}]}"
		next="${tracks_total[${j}]}"

		pregap_this_ref="gaps[${this},pre]"
		pregap_next_ref="gaps[${next},pre]"

		index0_this_ref="if_cue[${this},index,0]"
		index1_this_ref="if_cue[${this},index,1]"
		index0_next_ref="if_cue[${next},index,0]"
		index1_next_ref="if_cue[${next},index,1]"

		file_n_this_ref="tracks_file[${this}]"
		file_n_next_ref="tracks_file[${next}]"

		file_ref="if_cue[${!file_n_this_ref},filename]"

		sector_ref="tracks_sector[${this}]"

		start_ref="tracks_start[${this}]"

# If the CUE sheet specifies a pregap using the INDEX command, save that
# in the 'gaps' hash so it can later be converted to a PREGAP command.
		if [[ -n ${!index0_this_ref} && ${!pregap_this_ref} -eq 0 ]]; then
			gaps["${this},pre"]=$(( ${!index1_this_ref} - ${!index0_this_ref} ))
		fi

		if [[ -n ${!index0_next_ref} ]]; then
			gaps["${next},pre"]=$(( ${!index1_next_ref} - ${!index0_next_ref} ))
		fi

# Converts potential pregap frames to bytes, and adds it to the total
# bytes of the track position. This makes it possible for the
# 'copy_track' function to skip over the useless junk data in the
# pregap, when reading the track.
		bytes_pregap=$(( ${!pregap_this_ref} * ${!sector_ref} ))
		tracks_start["${this}"]=$(( bytes_total + bytes_pregap ))

# If this is the last track, get the track length by reading the size of
# the BIN file associated with this track.
		if [[ -z $next ]]; then
			get_size
			continue
		fi

# If the BIN file associated with this track is the same as the next
# track, get the track length by subtracting the start position of the
# current track from the position of the next track.
		if [[ ${!file_n_this_ref} -eq ${!file_n_next_ref} ]]; then
			frames=$(( ${!index1_next_ref} - ${!index1_this_ref} ))
			frames=$(( frames - ${!pregap_next_ref} ))

			bytes_track=$(( frames * ${!sector_ref} ))
			(( bytes_total += (bytes_track + bytes_pregap) ))

			tracks_length["${this}"]="$bytes_track"
		fi

# If the BIN file associated with this track is different from the next
# track, get the track length by reading the size of the BIN file
# associated with this track.
		if [[ ${!file_n_this_ref} -ne ${!file_n_next_ref} ]]; then
			get_size
		fi
	done
}

# Creates a function called 'loop_set', which will get the start
# positions, lengths, pregaps and postgaps for all tracks.
loop_set () {
	declare track_n

	for (( i = 0; i < ${#tracks_total[@]}; i++ )); do
		track_n="${tracks_total[${i}]}"

		gaps["${track_n},pre"]=0
		gaps["${track_n},post"]=0
	done

	get_length
}

read_cue
loop_set

printf '\n'

for (( i = 0; i < ${#tracks_total[@]}; i++ )); do
	track_n="${tracks_total[${i}]}"

	declare pregap_ref length_ref sector_ref frames

	pregap_ref="gaps[${track_n},pre]"
	length_ref="tracks_length[${track_n}]"
	sector_ref="tracks_sector[${track_n}]"

	frames=$(( ${!length_ref} / ${!sector_ref} ))

	printf 'Track %02d)\n' "$track_n"

	if [[ ${!pregap_ref} -gt 0 ]]; then
		printf '  pregap: %s , frames: %s\n' "$(time_convert "${!pregap_ref}")" "${!pregap_ref}"
	fi

	printf '  length: %s , frames: %s\n' "$(time_convert "$frames")" "$frames"
done

printf '\n'
