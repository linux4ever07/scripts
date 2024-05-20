#!/bin/bash

# This script is meant to take an input CUE/BIN file, extract the raw
# track(s) (data / audio) in whatever format the user has specified
# through script arguments. The script simply separates all the tracks
# of CUE/BIN files.

# Available audio formats are:
# * cdr (native CD audio)
# * ogg (Ogg Vorbis)
# * flac (Free Lossless Audio Codec)

# If no format is specified as an argument, the script will extract all
# 3 formats, and create CUE sheets for all 3 formats as well.

# The original purpose of the script is to take DOS games that have CD
# audio, and getting rid of the need to store the uncompressed audio.
# Ogg Vorbis is a lossy codec, so the files are much smaller and near
# the same quality. In the case of FLAC, it's a lossless format so the
# quality is identical to native CD audio. The only difference is FLAC
# is losslessly compressed so the files are slightly smaller. The
# generated CUE sheets can be used with DOSBox, using the 'IMGMOUNT'
# command.

# https://www.dosbox.com/wiki/IMGMOUNT

# Another use case for this script is to simply extract the OST from
# games, to listen to.

# The script will work with all kinds of games, including PS1 and Sega
# Saturn games. All that's required is that the disc image is in the
# CUE/BIN format. There are some other emulators out there that can
# handle FLAC and Ogg Vorbis tracks, like Mednafen, but support is not
# widespread. The main point of the script is being able to quickly
# extract music from CUE/BIN files.

# Yet another use case is to just split a CUE/BIN into its separate
# tracks, with the '-cdr' argument, without encoding the audio. Any
# CUE/BIN, that has multiple tracks, can be split. It doesn't need to
# have audio tracks.

# It's possible to do a byteswap on the audio tracks (to switch the
# endianness / byte order), through the optional '-byteswap' argument.
# This is needed in some cases, or audio tracks will be white noise if
# the endianness is wrong. So, it's easy to tell whether or not the byte
# order is correct.

# Pregaps are automatically stripped from the output BIN files, and are
# only symbolically represented in the generated CUE sheets as PREGAP
# commands. In the rare case that the disc has a hidden bonus track in
# the pregap for the 1st track, that will be stripped also as the script
# has no way of knowing the difference. If the pregap is longer than
# a couple of seconds, then it might contain a hidden track. The pregaps
# can be extracted separately with the optional '-pregaps' argument, if
# needed.

# The script is able to process CUE sheets that contain multiple FILE
# commands (list multiple BIN files). As an example, Redump will use 1
# BIN file per track, so that can be processed by the script directly in
# this case, without having to merge the CUE/BIN first.

# Earlier versions of the script used to depend on 'bchunk', which is a
# good program, but not needed anymore as other functions have replaced
# it.

declare -A if of

if[fn]=$(readlink -f "$1")
if[dn]=$(dirname "${if[fn]}")
if[bn]=$(basename "${if[fn]}")
if[bn_lc]="${if[bn],,}"

# Creates a function, called 'usage', which will print usage
# instructions and then quit.
usage () {
	cat <<USAGE

Usage: $(basename "$0") [cue] [...]

	Optional arguments:

-cdr
	Audio tracks will be output exclusively in CD audio format.

-ogg
	Audio tracks will be output exclusively in Ogg Vorbis.

-flac
	Audio tracks will be output exclusively in FLAC.

-sox
	Uses 'sox' instead of 'ffmpeg' to convert CD audio to WAV.

-byteswap
	Reverses the endianness / byte order of the audio tracks.

-pregaps
	Outputs pregap data exclusively.

USAGE

	exit
}

# If input is not a real file, or it has the wrong extension, print
# usage and quit.
if [[ ! -f ${if[fn]} || ${if[bn_lc]##*.} != 'cue' ]]; then
	usage
fi

declare mode byteswap pregaps session type
declare -a format tracks_total files_total
declare -a of_cue_cdr of_cue_ogg of_cue_flac
declare -A regex if_info gaps bytes
declare -A audio_types audio_types_run

audio_types=([cdr]='cdr' [ogg]='wav' [flac]='wav')

mode='ffmpeg'
byteswap=0
pregaps=0

session="${RANDOM}-${RANDOM}"

# The loop below handles the arguments to the script.
shift

while [[ $# -gt 0 ]]; do
	case "$1" in
		'-cdr')
			audio_types_run[cdr]=1

			shift
		;;
		'-ogg')
			audio_types_run[ogg]=1

			shift
		;;
		'-flac')
			audio_types_run[flac]=1

			shift
		;;
		'-sox')
			mode='sox'

			shift
		;;
		'-byteswap')
			byteswap=1

			shift
		;;
		'-pregaps')
			pregaps=1

			shift
		;;
		*)
			usage
		;;
	esac
done

if [[ ${#audio_types_run[@]} -eq 0 ]]; then
	for type in "${!audio_types[@]}"; do
		audio_types_run["${type}"]=1
	done
fi

of[name]="${if[bn_lc]%.*}"
of[name]=$(sed -E 's/ +/_/g' <<<"${of[name]}")

of[dn]="${PWD}/${of[name]}-${session}"

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

# Creates a function, called 'check_cmd', which will check if the
# necessary commands are installed. If any of the commands are missing,
# print them and quit.
check_cmd () {
	declare cmd
	declare -a missing_pkg

	for cmd in "$@"; do
		command -v "$cmd" 1>&-

		if [[ $? -ne 0 ]]; then
			missing_pkg+=("$cmd")
		fi
	done

	if [[ ${#missing_pkg[@]} -gt 0 ]]; then
		printf '\n%s\n\n' 'You need to install the following through your package manager:'
		printf '%s\n' "${missing_pkg[@]}"
		printf '\n'

		exit
	fi
}

# Creates a function, called 'run_cmd', which will be used to run
# external commands, capture their output, and print the output (and
# quit) if the command fails.
run_cmd () {
	declare exit_status
	declare -a cmd_stdout

	mapfile -t cmd_stdout < <(eval "$@" 2>&1; printf '%s\n' "$?")

	exit_status="${cmd_stdout[-1]}"
	unset -v cmd_stdout[-1]

# Prints the output from the command if it has a non-zero exit status,
# and then quits.
	if [[ $exit_status != '0' ]]; then
		printf '%s\n' "${cmd_stdout[@]}"
		printf '\n'

		exit
	fi
}

# Creates a function, called 'get_files', which will be used to generate
# file lists to be used by other functions.
get_files () {
	declare glob

	for glob in "$@"; do
		compgen -G "$glob"
	done | sort -n
}

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

# Creates a function, called 'block_calc', which will be used to get the
# optimal block size to use in the 'copy_track' function when reading
# and writing tracks using 'dd'. Bigger block sizes makes the process
# faster. The reason for being able to handle variable block sizes is
# that it's technically possible for a CUE sheet to contain tracks that
# have different sector sizes. And that will affect the start positions
# of tracks. This function counts down from 16KB, subtracting 4 bytes at
# each iteration of the loop, until a matching block size is found.
# We're using 4 byte increments cause that guarantees the block size
# will be divisible by the common CD sector sizes:
# * 2048
# * 2324
# * 2336
# * 2352
# * 2448
block_calc () {
	declare bytes1 bytes2 block_diff1 block_diff2

	bytes1="$1"
	bytes2="$2"

	block_size=16384

	block_diff1=$(( bytes1 % block_size ))
	block_diff2=$(( bytes2 % block_size ))

	until [[ $block_diff1 -eq 0 && $block_diff2 -eq 0 ]]; do
		(( block_size -= 4 ))

		block_diff1=$(( bytes1 % block_size ))
		block_diff2=$(( bytes2 % block_size ))
	done
}

# Creates a function, called 'copy_track', which will extract the raw
# binary data for the current track number, from the BIN file.
copy_track () {
	declare file_n_ref file_ref type_ref start_ref length_ref
	declare ext block_size skip count
	declare -a args

	file_n_ref="if_info[${track_n},file]"
	file_ref="if_info[${!file_n_ref},file_name]"

	type_ref="if_info[${track_n},type]"

# Depending on whether the track type is data or audio, use the
# appropriate file name extension for the output file.
	case "${!type_ref}" in
		'data')
			ext='bin'
		;;
		'audio')
			ext='cdr'
		;;
	esac

	of[bn]=$(printf '%s%02d.%s' "${of[name]}" "$track_n" "$ext")
	of[fn]="${of[dn]}/${of[bn]}"

# Creates the first part of the 'dd' command.
	args=(dd if=\""${!file_ref}"\" of=\""${of[fn]}"\")

# Does a byteswap if the script was run with the '-byteswap' option, and
# the track is audio.
	if [[ $byteswap -eq 1 && ${!type_ref} == 'audio' ]]; then
		args+=(conv=swab)
	fi

# Gets the start position, and length, of the track.
	start_ref="bytes[${track_n},track,start]"
	length_ref="bytes[${track_n},track,length]"

	if [[ $pregaps -eq 1 ]]; then
		start_ref="bytes[${track_n},pregap,start]"
		length_ref="bytes[${track_n},pregap,length]"
	fi

# If the track length is '0', don't bother copying it, but instead
# return from this function.
	if [[ ${!length_ref} -eq 0 ]]; then
		return
	fi

# Gets the optimal block size to use with 'dd'.
	block_calc "${!start_ref}" "${!length_ref}"

	args+=(bs=\""${block_size}"\")

	skip=$(( ${!start_ref} / block_size ))
	count=$(( ${!length_ref} / block_size ))

# If the start position of the track is greater than '0', skip blocks
# until the start of the track.
	if [[ $skip -gt 0 ]]; then
		args+=(skip=\""${skip}"\")
	fi

# If the track length is greater than '0', copy only a limited number of
# blocks.
	if [[ $count -gt 0 ]]; then
		args+=(count=\""${count}"\")
	fi

# Prints track information.
	printf 'Track %02d)\n' "$track_n"
	printf '  block: %s\n' "$block_size"
	printf '  start: %s\n' "$skip"
	printf '  length: %s\n\n' "$count"

# Runs 'dd'.
	run_cmd "${args[@]}"

# Adds file name to list.
	files_total["${track_n}"]="${of[bn]}"
}

# Creates a function, called 'copy_all_tracks', which will extract the
# raw binary data for all tracks (i.e. separate the tracks).
copy_all_tracks () {
	declare track_n

	for (( i = 0; i < ${#tracks_total[@]}; i++ )); do
		track_n="${tracks_total[${i}]}"

		copy_track
	done
}

# Creates a function, called 'cdr2wav', which will convert the extracted
# CDR files to WAV (using 'ffmpeg' or 'sox').
cdr2wav () {
	declare type_tmp
	declare -a files

	type_tmp="${audio_types[${type}]}"

	mapfile -t files < <(get_files "*.cdr")

# If type is not 'wav' or there are no CDR files, return from this
# function.
	if [[ $type_tmp != 'wav' || ${#files[@]} -eq 0 ]]; then
		return
	fi

	for (( i = 0; i < ${#files[@]}; i++ )); do
		if[cdr]="${files[${i}]}"
		of[wav]="${if[cdr]%.*}.wav"

		if [[ -f ${of[wav]} ]]; then
			continue
		fi

		declare args_ref
		declare -a args_ffmpeg args_sox

# Creates the command arguments for 'ffmpeg' and 'sox'.
		args_ffmpeg=(-ar 44.1k -ac 2)
		args_ffmpeg=(ffmpeg -f s16le "${args_ffmpeg[@]}" -i \""${if[cdr]}"\" -c:a pcm_s16le "${args_ffmpeg[@]}" \""${of[wav]}"\")

		args_sox=(sox -L \""${if[cdr]}"\" \""${of[wav]}"\")

# Depending on what the mode is, run 'ffmpeg' or 'sox' on the CDR file,
# specifying 'little-endian' for the input.
		args_ref="args_${mode}[@]"

		run_cmd "${!args_ref}"

# If 'cdr' is not among the chosen audio types, delete the CDR file.
		if [[ -z ${audio_types_run[cdr]} ]]; then
			rm "${if[cdr]}" || exit
		fi

		unset -v args_ref args_ffmpeg args_sox
	done
}

# Creates a function, called 'encode_audio', which will encode the WAVs
# created by previously run functions.
encode_audio () {
	declare type_tmp
	declare -a files

	type_tmp="${audio_types[${type}]}"

	mapfile -t files < <(get_files "*.wav")

# If type is not 'wav' or there are no WAV files, return from this
# function. This makes it possible for the script to finish normally,
# even if there are no audio tracks.
	if [[ $type_tmp != 'wav' || ${#files[@]} -eq 0 ]]; then
		return
	fi

	case "$type" in
		'ogg')
			oggenc --quality=10 "${files[@]}" || exit
		;;
		'flac')
			flac -8 "${files[@]}" || exit
		;;
	esac
}

# Creates a function, called 'create_cue', which will create a new CUE
# sheet, based on the file list created by the 'copy_track' function.
create_cue () {
	declare index_string track_n line_ref type_tmp
	declare -a offset
	declare -A ext_format

	index_string='INDEX 01 00:00:00'

	offset=('  ' '    ')
	ext_format=([bin]='BINARY' [cdr]='BINARY' [ogg]='OGG' [flac]='FLAC')

	type_tmp="${audio_types[${type}]}"

# Creates a function, called 'set_track_info', which will add FILE,
# TRACK, PREGAP, INDEX and POSTGAP commands. Pregap and postgap is only
# added if they exist in the source CUE sheet.
	set_track_info () {
		declare mode_ref format_ref track_string
		declare pregap_ref postgap_ref time

		mode_ref="if_info[${track_n},mode]"
		format_ref="ext_format[${ext}]"

		track_string=$(printf 'TRACK %02d %s' "$track_n" "${!mode_ref}")

		eval of_cue_"${type}"+=\(\""FILE \\\"${fn}.${ext}\\\" ${!format_ref}"\"\)
		eval of_cue_"${type}"+=\(\""${offset[0]}${track_string}"\"\)

		pregap_ref="gaps[${track_n},pre]"
		postgap_ref="gaps[${track_n},post]"

		if [[ ${!pregap_ref} -gt 0 ]]; then
			time=$(time_convert "${!pregap_ref}")
			eval of_cue_"${type}"+=\(\""${offset[1]}PREGAP ${time}"\"\)
		fi

		eval of_cue_"${type}"+=\(\""${offset[1]}${index_string}"\"\)

		if [[ ${!postgap_ref} -gt 0 ]]; then
			time=$(time_convert "${!postgap_ref}")
			eval of_cue_"${type}"+=\(\""${offset[1]}POSTGAP ${time}"\"\)
		fi
	}

# Goes through the list of files produced by previously run functions,
# and creates a new CUE sheet based on that.
	for (( i = 0; i < ${#tracks_total[@]}; i++ )); do
		track_n="${tracks_total[${i}]}"
		line_ref="files_total[${track_n}]"

		if [[ -z ${!line_ref} ]]; then
			continue
		fi

		declare fn ext

# Separates file name and extension.
		if [[ ! ${!line_ref} =~ ${regex[fn]} ]]; then
			continue
		fi

		fn="${BASH_REMATCH[1]}"
		ext="${BASH_REMATCH[2]}"

# If the extension is 'cdr', then the correct extension is the same as
# the current audio type.
		if [[ $ext == 'cdr' ]]; then
			ext="$type"
		fi

# Sets all the relevant file / track information.
		set_track_info

		unset -v fn ext
	done
}

# Creates a function, called 'print_cue', which will print the created
# CUE sheet(s) to the terminal, and to the output file.
print_cue () {
	declare lines_ref

	for type in "${!audio_types_run[@]}"; do
		of[fn]="${of[dn]}/${of[name]}01_${type}.cue"
		lines_ref="of_cue_${type}[@]"

		printf '\n'
		printf '%s\r\n' "${!lines_ref}" | tee "${of[fn]}"
	done
}

# Creates a function, called 'clean_up', which deletes temporary files:
# * Potential WAV files
clean_up () {
	declare -a files

	mapfile -t files < <(get_files "*.wav")

	if [[ ${#files[@]} -eq 0 ]]; then
		return
	fi

	rm "${files[@]}" || exit
}

# Checks if 'oggenc', 'flac' are installed. Depending on which mode is
# set, check if 'ffmpeg' or 'sox' is installed.
check_cmd 'oggenc' 'flac' "$mode"

# Creates the output directory and changes into it.
mkdir "${of[dn]}" || exit
cd "${of[dn]}" || exit

printf '\nOutput:\n%s\n\n' "${of[dn]}"

# Runs the functions.
read_cue
get_gaps
get_length

copy_all_tracks

for type in "${!audio_types_run[@]}"; do
	cdr2wav
	encode_audio
	create_cue
done

if [[ $pregaps -eq 0 ]]; then
	print_cue
fi

printf '\n'

clean_up
