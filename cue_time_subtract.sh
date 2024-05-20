#!/bin/bash

# This script is meant to get the length of all individual tracks in a
# CUE sheet.

declare -A if of

if[fn]=$(readlink -f "$1")
if[dn]=$(dirname "${if[fn]}")
if[bn]=$(basename "${if[fn]}")
if[bn_lc]="${if[bn],,}"

# Creates a function, called 'usage', which will print usage
# instructions and then quit.
usage () {
	printf '\n%s\n\n' "Usage: $(basename "$0") [cue]"
	exit
}

# If input is not a real file, or it has the wrong extension, print
# usage and quit.
if [[ ! -f ${if[fn]} || ${if[bn_lc]##*.} != 'cue' ]]; then
	usage
fi

declare track_n frames
declare pregap_ref length_ref sector_ref
declare -a format tracks_total
declare -A regex if_info gaps bytes

format[0]='^[0-9]+$'
format[1]='^([0-9]{2,}):([0-9]{2}):([0-9]{2})$'
format[2]='[0-9]{2,}:[0-9]{2}:[0-9]{2}'
format[3]='^(FILE) +(.*) +(.*)$'
format[4]='^(TRACK) +([0-9]{2,}) +(.*)$'
format[5]="^(PREGAP) +(${format[2]})$"
format[6]="^(INDEX) +([0-9]{2,}) +(${format[2]})$"
format[7]="^(POSTGAP) +(${format[2]})$"

regex[blank]='^[[:blank:]]*(.*)[[:blank:]]*$'
regex[quotes]='^\"(.*)\"$'
regex[path]='^(.*[\\\/])(.*)$'
regex[fn]='^(.*)\.([^.]*)$'

regex[data]='^MODE([0-9])\/([0-9]{4})$'
regex[audio]='^AUDIO$'

# Creates a function, called 'time_convert', which converts track
# timestamps back and forth between the time (mm:ss:ff) format and
# frames / sectors.
time_convert () {
	declare time m s f

	time="$1"

# If argument is in the mm:ss:ff format...
	if [[ $time =~ ${format[1]} ]]; then
		m="${BASH_REMATCH[1]#0}"
		s="${BASH_REMATCH[2]#0}"
		f="${BASH_REMATCH[3]#0}"

# Converts minutes and seconds to frames, and adds all the numbers
# together.
		m=$(( m * 60 * 75 ))
		s=$(( s * 75 ))

		time=$(( m + s + f ))

# If argument is in the frame format...
	elif [[ $time =~ ${format[0]} ]]; then
		f="$time"

# Converts frames to seconds and minutes.
		s=$(( f / 75 ))
		m=$(( s / 60 ))

		f=$(( f % 75 ))
		s=$(( s % 60 ))

		time=$(printf '%02d:%02d:%02d' "$m" "$s" "$f")
	fi

	printf '%s' "$time"
}

# Creates a function, called 'read_cue', which will read the source CUE
# sheet, get all the relevant information from it and store that in
# variables. It will also add full path to file names listed in the CUE
# sheet.
read_cue () {
	declare line file_n track_n index_n frames error
	declare -a match lines files not_found wrong_format wrong_mode

	declare -a error_types
	declare -A error_msgs

	file_n=0
	track_n=0
	index_n=0

	error_types=('not_found' 'wrong_format' 'wrong_mode')
	error_msgs[no_files]='No files were found in CUE sheet!'
	error_msgs[not_found]='The files below were not found:'
	error_msgs[wrong_format]='The files below have the wrong format:'
	error_msgs[wrong_mode]='The tracks below have an unrecognized mode:'

# Reads the source CUE sheet into RAM.
	mapfile -t lines < <(tr -d '\r' <"${if[fn]}" | sed -E "s/${regex[blank]}/\1/")

# This loop processes each line in the CUE sheet, and stores all the
# relevant information in the 'if_info' hash.
	for (( i = 0; i < ${#lines[@]}; i++ )); do
		line="${lines[${i}]}"

# If line is a FILE command...
		if [[ $line =~ ${format[3]} ]]; then
			match=("${BASH_REMATCH[@]:1}")

# Strips quotes that may be present in the CUE sheet.
			if [[ ${match[1]} =~ ${regex[quotes]} ]]; then
				match[1]="${BASH_REMATCH[1]}"
			fi

# Strips path that may be present in the CUE sheet.
			if [[ ${match[1]} =~ ${regex[path]} ]]; then
				match[1]="${BASH_REMATCH[2]}"
			fi

# Adds full path to the basename.
			match[1]="${if[dn]}/${match[1]}"

# Resolves the path to the real file, in case it's a symlink.
			match[1]=$(readlink -f "${match[1]}")

# If file can't be found, or format isn't binary, then it's useless even
# trying to process this CUE sheet.
			if [[ ! -f ${match[1]} ]]; then
				not_found+=("${match[1]}")
			fi

			if [[ ${match[2]} != 'BINARY' ]]; then
				wrong_format+=("${match[1]}")
			fi

			files+=("${match[1]}")

			(( file_n += 1 ))

			if_info["${file_n},file_name"]="${match[1]}"
			if_info["${file_n},file_format"]="${match[2]}"

			continue
		fi

# If line is a TRACK command...
		if [[ $line =~ ${format[4]} ]]; then
			match=("${BASH_REMATCH[@]:1}")

			track_n="${match[1]#0}"

# Saves the file number associated with this track.
			if_info["${track_n},file"]="$file_n"

# Saves the current track number (and in effect, every track number) in
# an array so the exact track numbers can be referenced later.
			tracks_total+=("$track_n")

# Figures out if this track is data or audio, and saves the sector size.
# Typical sector size is 2048 bytes for data CDs, and 2352 for audio. If
# track mode was not recognized, then it's useless even trying to
# process this CUE sheet.
			if [[ ${match[2]} =~ ${regex[data]} ]]; then
				if_info["${track_n},type"]='data'
				if_info["${track_n},sector"]="${BASH_REMATCH[2]}"
			elif [[ ${match[2]} =~ ${regex[audio]} ]]; then
				if_info["${track_n},type"]='audio'
				if_info["${track_n},sector"]=2352
			else
				wrong_mode+=("$track_n")
			fi

			if_info["${track_n},mode"]="${match[2]}"

			continue
		fi

# If line is a PREGAP command...
		if [[ $line =~ ${format[5]} ]]; then
			match=("${BASH_REMATCH[@]:1}")

			frames=$(time_convert "${match[1]}")
			if_info["${track_n},pregap"]="$frames"

			continue
		fi

# If line is an INDEX command...
		if [[ $line =~ ${format[6]} ]]; then
			match=("${BASH_REMATCH[@]:1}")

			index_n="${match[1]#0}"

			frames=$(time_convert "${match[2]}")
			if_info["${track_n},index,${index_n}"]="$frames"

			continue
		fi

# If line is a POSTGAP command...
		if [[ $line =~ ${format[7]} ]]; then
			match=("${BASH_REMATCH[@]:1}")

			frames=$(time_convert "${match[1]}")
			if_info["${track_n},postgap"]="$frames"

			continue
		fi
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

# Creates a function, called 'get_gaps', which will get pregap and
# postgap from the CUE sheet for all tracks. If there's both a pregap
# specified using the PREGAP command and INDEX command, those values
# will be added together. However, a CUE sheet is highly unlikely to
# specify a pregap twice like that.
get_gaps () {
	declare track_n frames
	declare index0_ref index1_ref
	declare pregap_ref postgap_ref

	for (( i = 0; i < ${#tracks_total[@]}; i++ )); do
		track_n="${tracks_total[${i}]}"

		gaps["${track_n},index"]=0
		gaps["${track_n},pre"]=0
		gaps["${track_n},post"]=0

		index0_ref="if_info[${track_n},index,0]"
		index1_ref="if_info[${track_n},index,1]"

		pregap_ref="if_info[${track_n},pregap]"
		postgap_ref="if_info[${track_n},postgap]"

# If the CUE sheet specifies a pregap using the INDEX command, save that
# in the 'gaps' hash so it can later be converted to a PREGAP command.
		if [[ -n ${!index0_ref} ]]; then
			frames=$(( ${!index1_ref} - ${!index0_ref} ))

			(( gaps[${track_n},index] += frames ))
			(( gaps[${track_n},pre] += frames ))
		fi

# If the CUE sheet contains PREGAP or POSTGAP commands, save that in the
# 'gaps' hash. Add it to the value that might already be there, cause of
# pregaps specified by INDEX commands.
		if [[ -n ${!pregap_ref} ]]; then
			(( gaps[${track_n},pre] += ${!pregap_ref} ))
		fi

		if [[ -n ${!postgap_ref} ]]; then
			(( gaps[${track_n},post] += ${!postgap_ref} ))
		fi
	done
}

# Creates a function, called 'get_length', which will get the start
# position, and length, (in bytes) of all tracks in the respective BIN
# files.
get_length () {
	declare this next
	declare bytes_pregap bytes_track bytes_total frames
	declare pregap_this_ref pregap_next_ref
	declare index1_this_ref index1_next_ref
	declare file_n_this_ref file_n_next_ref file_ref
	declare sector_ref start_ref

	bytes_total=0

# Creates a function, called 'get_size', which will get the track length
# by reading the size of the BIN file associated with this track. This
# function will also reset the 'bytes_total' variable to '0' (as the
# current track is last in the current BIN file).
	get_size () {
		declare size

		size=$(stat -c '%s' "${!file_ref}")

		bytes_track=$(( size - ${!start_ref} ))
		bytes_total=0

		bytes["${this},track,length"]="$bytes_track"
	}

	for (( i = 0; i < ${#tracks_total[@]}; i++ )); do
		j=$(( i + 1 ))

		this="${tracks_total[${i}]}"
		next="${tracks_total[${j}]}"

		pregap_this_ref="gaps[${this},index]"
		pregap_next_ref="gaps[${next},index]"

		index1_this_ref="if_info[${this},index,1]"
		index1_next_ref="if_info[${next},index,1]"

		file_n_this_ref="if_info[${this},file]"
		file_n_next_ref="if_info[${next},file]"

		file_ref="if_info[${!file_n_this_ref},file_name]"

		sector_ref="if_info[${this},sector]"

		start_ref="bytes[${this},track,start]"

# Converts potential pregap frames to bytes, and adds it to the total
# bytes of the track position. This makes it possible for the
# 'copy_track' function to skip over the useless junk data in the
# pregap, when reading the track.
		bytes_pregap=$(( ${!pregap_this_ref} * ${!sector_ref} ))

		bytes["${this},pregap,start"]="$bytes_total"
		bytes["${this},pregap,length"]="$bytes_pregap"

		bytes["${this},track,start"]=$(( bytes_total + bytes_pregap ))

# If this is the last track, get the track length by reading the size of
# the BIN file associated with this track.
		if [[ -z $next ]]; then
			get_size

			continue
		fi

# If the BIN file associated with this track is the same as the next
# track, get the track length by subtracting the start position of this
# track from the position of the next track.
		if [[ ${!file_n_this_ref} -eq ${!file_n_next_ref} ]]; then
			frames=$(( ${!index1_next_ref} - ${!index1_this_ref} ))
			(( frames -= ${!pregap_next_ref} ))

			bytes_track=$(( frames * ${!sector_ref} ))
			(( bytes_total += (bytes_track + bytes_pregap) ))

			bytes["${this},track,length"]="$bytes_track"

			continue
		fi

# If the BIN file associated with this track is different from the next
# track, get the track length by reading the size of the BIN file
# associated with this track.
		if [[ ${!file_n_this_ref} -ne ${!file_n_next_ref} ]]; then
			get_size

			continue
		fi
	done
}

read_cue
get_gaps
get_length

printf '\n'

for (( i = 0; i < ${#tracks_total[@]}; i++ )); do
	track_n="${tracks_total[${i}]}"

	pregap_ref="gaps[${track_n},index]"
	length_ref="bytes[${track_n},track,length]"
	sector_ref="if_info[${track_n},sector]"

	frames=$(( ${!length_ref} / ${!sector_ref} ))

	printf 'Track %02d)\n' "$track_n"

	if [[ ${!pregap_ref} -gt 0 ]]; then
		printf '  pregap: %s , frames: %s\n' "$(time_convert "${!pregap_ref}")" "${!pregap_ref}"
	fi

	printf '  length: %s , frames: %s\n' "$(time_convert "$frames")" "$frames"
done

printf '\n'
