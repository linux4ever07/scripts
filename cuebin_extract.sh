#!/bin/bash

# This script is meant to take an input BIN/CUE file, extract the raw
# track(s) (data / audio) in whatever format the user has specified
# through script arguments. The script simply separates all the tracks
# of BIN/CUE files.

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
# BIN/CUE format. Though, I'm not sure if there's emulators that can
# handle FLAC or Ogg Vorbis tracks. The point would mainly be to listen
# to the music.

# Yet another use case is to just split a BIN/CUE into its separate
# tracks, with the '-cdr' argument, without encoding the audio.

# It's possible to do a byteswap on the audio tracks (to switch the
# endianness / byte order), through the optional '-byteswap' argument.
# This is needed in some cases, or audio tracks will be white noise if
# the endianness is wrong. So, it's easy to tell whether or not the byte
# order is correct.

# ISO files produced by 'bchunk' are discarded, and data tracks are
# instead copied directly from the source BIN file, calculating the
# length of tracks based on information gathered from the CUE sheet.

# Since the 'copy_track' function is now able to correctly copy any
# track from the source BIN file, it's possible to make this script not
# depend on 'bchunk' anymore. The default mode is to use 'bchunk', but
# if the user passes the '-sox' argument to the script, then 'sox' is
# used instead. The end result is identical either way. It's just nice
# to have a way out, in case a certain program is not available.

# The advantage of using the '-sox' argument, is that the script is then
# able to process CUE sheets that contain multiple FILE commands (list
# multiple BIN files). As an example, Redump will use 1 BIN file /
# track, so that can be processed by the script directly in this case,
# without having to merge the BIN/CUE first.

# It may also be possible to use 'ffmpeg' in a similar way to how 'sox'
# is used in the 'cdr2wav' function. But I did not manage to get it
# working. The command would probably be something like this:

# ffmpeg -i in.cdr -ar 44.1k -ac 2 -f pcm_s16le out.wav

if=$(readlink -f "$1")
if_bn=$(basename "$if")
if_bn_lc="${if_bn,,}"

# Creates a function called 'usage', which will print usage and quit.
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
	Uses 'sox' instead of 'bchunk' to convert CD audio to WAV.

-byteswap
	Reverses the endianness / byte order of the audio tracks.

USAGE

	exit
}

# If $if is not a real file, or it has the wrong extension, print usage
# and quit.
if [[ ! -f $if || ${if_bn_lc##*.} != 'cue' ]]; then
	usage
fi

declare -A audio_types audio_types_run

audio_types=([cdr]='cdr' [ogg]='wav' [flac]='wav')

mode='bchunk'
byteswap=0

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

session="${RANDOM}-${RANDOM}"

if_name="${if_bn_lc%.*}"
of_name=$(sed -E 's/[[:blank:]]+/_/g' <<<"$if_name")

if_dn=$(dirname "$if")
of_dn="${PWD}/${of_name}-${session}"

cue="$if"
cue_tmp="/dev/shm/${of_name}-${session}.cue"

declare -A regex
declare -a format offset sector

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
regex[fn]='^(.*)\.([^.]*)$'

regex[data]='^MODE[0-9]+/[0-9]+$'
regex[audio]='^AUDIO$'

index_default='INDEX 01 00:00:00'
offset=('  ' '    ')

# 2048 bytes is normally the sector size for data CDs / tracks, and 2352
# bytes is the size of audio sectors.
sector=('2048' '2352')

declare -A if_cue gaps
declare -a tracks_file tracks_type frames
declare -a files_cdr files_wav of_cue_cdr of_cue_ogg of_cue_flac

# trap ctrl-c and call iquit()
trap iquit INT

# Creates a function called 'iquit', which removes the temporary CUE
# sheet and quits. It's used throughout the script to quit when a
# command fails, or when a SIGINT signal is caught.
iquit () {
	rm -f "$cue_tmp"
	exit
}

# Creates a function called 'check_cmd', which will check if the
# necessary commands are installed.
check_cmd () {
	for cmd in "$@"; do
		command -v "$cmd" 1>&-

		if [[ $? -ne 0 ]]; then
			printf '\n%s\n\n' "You need to install '${cmd}' through your package manager!"
			exit
		fi
	done
}

# Creates a function called 'get_files', which will be used to generate
# file lists to be used by other functions.
get_files () {
	declare -a files_tmp

	shopt -s nullglob

	files_tmp=($@)

	shopt -u nullglob

	if [[ ${#files_tmp[@]} -gt 0 ]]; then
		printf '%s\n' "${files_tmp[@]}" | sort -n
	fi
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

		s=$(( f / 75 ))
		m=$(( s / 60 ))

		f=$(( f % 75 ))
		s=$(( s % 60 ))

		time=$(printf '%02d:%02d:%02d' "$m" "$s" "$f")
	fi

	printf '%s' "$time"
}

# Creates a function called 'read_cue', which will read the source CUE
# sheet, add full path to file names listed in the CUE sheet, and create
# a new temporary CUE sheet in /dev/shm based on this.
read_cue () {
	declare file_n track_n
	declare -a files not_found wrong_format lines lines_tmp

	file_n=0
	track_n=0

# Creates a function called 'handle_command', which will process each
# line in the CUE sheet and store all the relevant information in the
# 'if_cue' hash.
	handle_command () {
# If line is a FILE command...
		if [[ $1 =~ ${format[3]} ]]; then
			match=("${BASH_REMATCH[@]:1}")

			fn=$(tr -d '"' <<<"${match[1]}" | sed -E "s/${regex[path]}//")
			fn="${if_dn}/${fn}"

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

			tracks_file["${track_n}"]="$file_n"

			if [[ ${match[2]} =~ ${regex[data]} ]]; then
				tracks_type["${track_n}"]='data'
			fi

			if [[ ${match[2]} =~ ${regex[audio]} ]]; then
				tracks_type["${track_n}"]='audio'
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

# If a string has been created, add it to the 'lines_tmp' array.
		if [[ -n $string ]]; then
			lines_tmp+=("$string")
		fi
	}

# Reads the source CUE sheet and processes the lines.
	mapfile -t lines < <(tr -d '\r' <"$cue" | sed -E "s/${regex[blank]}/\1/")

	for (( i = 0; i < ${#lines[@]}; i++ )); do
		line="${lines[${i}]}"
		handle_command "$line"
	done

# If there's multiple FILE commands in the CUE sheet, ask the user to
# create a merged BIN/CUE. But only if the mode is 'bchunk'.
	if [[ ${#files[@]} -gt 1 && $mode == 'bchunk' ]]; then
		cat <<MERGE

This CUE sheet contains multiple FILE commands!

You need to merge all the containing files into one BIN file, using a
tool like PowerISO.

MERGE

		exit
	fi

# Lists file names that are not real files.
	if [[ ${#not_found[@]} -gt 0 ]]; then
		printf '\n%s\n\n' 'The files below were not found:'
		printf '%s\n' "${not_found[@]}"
		printf '\n'

		exit
	fi

# Lists file names that have the wrong format.
	if [[ ${#wrong_format[@]} -gt 0 ]]; then
		printf '\n%s\n\n' 'The files below have the wrong format:'
		printf '%s\n' "${wrong_format[@]}"
		printf '\n'

		exit
	fi

# Writes the temporary CUE sheet to /dev/shm.
	printf '%s\n' "${lines_tmp[@]}" > "$cue_tmp"
}

# Creates a function called 'get_frames', which will get the length of
# a track in the BIN file, subtracting pregap if it exists as part of
# the INDEX commands.
get_frames () {
	this="$1"
	next=$(( this + 1 ))

	declare file_this_ref file_next_ref index_this_ref index_next_ref
	declare frames_tmp

	file_this_ref="tracks_file[${this}]"
	file_next_ref="tracks_file[${next}]"

	if [[ ${!file_this_ref} -ne ${!file_next_ref} ]]; then
		return
	fi

	index_this_ref="if_cue[${this},index,1]"
	index_next_ref="if_cue[${next},index,0]"

	if [[ -z ${!index_next_ref} ]]; then
		index_next_ref="if_cue[${next},index,1]"
	fi

	if [[ -z ${!index_next_ref} ]]; then
		return
	fi

	frames_tmp=$(( ${!index_next_ref} - ${!index_this_ref} ))
	frames["${this}"]="$frames_tmp"
}

# Creates a function called 'get_gaps', which will get pregap and
# postgap from the CUE sheet for the track number given as argument.
# If there's both a pregap specified using the PREGAP command and INDEX
# command, those values will be added together. However, a CUE sheet is
# highly unlikely to specify a pregap twice like that.
get_gaps () {
	track_n="$1"

	declare index_0_ref index_1_ref frames_tmp pregap postgap

	pregap=0
	postgap=0

# If the CUE sheet specifies a pregap using the INDEX command, save that
# in the 'gaps' hash so it can later be converted to a PREGAP command.
	index_0_ref="if_cue[${track_n},index,0]"
	index_1_ref="if_cue[${track_n},index,1]"

	if [[ -n ${!index_0_ref} && -n ${!index_1_ref} ]]; then
		frames_tmp=$(( ${!index_1_ref} - ${!index_0_ref} ))
		pregap=$(( pregap + frames_tmp ))
	fi

# If the CUE sheet contains PREGAP or POSTGAP commands, save that in the
# 'gaps' hash.
	pregap_ref="if_cue[${track_n},pregap]"
	postgap_ref="if_cue[${track_n},postgap]"

	if [[ -n ${!pregap_ref} ]]; then
		pregap=$(( pregap + ${!pregap_ref} ))
	fi

	if [[ -n ${!postgap_ref} ]]; then
		postgap=$(( postgap + ${!postgap_ref} ))
	fi

	gaps["${track_n},pre"]="$pregap"
	gaps["${track_n},post"]="$postgap"
}

# Creates a function called 'loop_set', which will get the length of all
# tracks in the BIN file (except the last one). And get pregaps and
# postgaps of all tracks.
loop_set () {
	declare track_n

	for (( i = 0; i < ${#tracks_file[@]}; i++ )); do
		track_n=$(( i + 1 ))

		get_frames "$track_n"
		get_gaps "$track_n"
	done
}

# Creates a function called 'copy_track', which will extract the raw
# binary data for the track number given as argument, from the BIN file.
copy_track () {
	track_n="$1"
	track_type="$2"

	declare file_n_ref bin_ref frames_ref index_ref
	declare ext count skip
	declare -a args cmd_stdout

	file_n_ref="tracks_file[${track_n}]"
	bin_ref="if_cue[${!file_n_ref},filename]"

# Depending on whether the track type is data or audio, use the
# appropriate file name extension for the output file.
	case "$track_type" in
		'data')
			ext='bin'
		;;
		'audio')
			ext='cdr'
		;;
	esac

	of_bin=$(printf '%s/%s%02d.%s' "$of_dn" "$of_name" "$track_n" "$ext")

# Creates the first part of the 'dd' command.
	args=(dd if=\""${!bin_ref}"\" of=\""${of_bin}"\" bs=\""${sector[1]}"\")

# Does a byteswap if the script was run with the '-byteswap' option, and
# the track is audio.
	if [[ $byteswap -eq 1 && $track_type == 'audio' ]]; then
		args+=(conv=swab)
	fi

# Gets the length of the track, unless it's the last track, in which
# case the length will be absent from the 'frames' array. Also, gets the
# start position of the track.
	frames_ref="frames[${track_n}]"
	index_ref="if_cue[${track_n},index,1]"

	count=0
	skip=0

	if [[ -n ${!frames_ref} ]]; then
		count="${!frames_ref}"
	fi

	if [[ -n ${!index_ref} ]]; then
		skip="${!index_ref}"
	fi

# If the track length is greater than '0', copy only a limited number of
# frames.
	if [[ $count -gt 0 ]]; then
		args+=(count=\""${count}"\")
	fi

# If the start position of the track is greater than '0', skip frames.
	if [[ $skip -gt 0 ]]; then
		args+=(skip=\""${skip}"\")
	fi

# Runs 'dd'.
	mapfile -t cmd_stdout < <(eval "${args[@]}" 2>&1; printf '%s\n' "$?")

	exit_status="${cmd_stdout[-1]}"
	unset -v cmd_stdout[-1]

# Prints the output from 'dd' if it quits with a non-zero exit
# status.
	if [[ $exit_status != '0' ]]; then
		printf '%s\n' "${cmd_stdout[@]}"
		iquit
	fi
}

# Creates a function called 'copy_track_type', which will extract the
# raw binary data for all tracks of either the data or audio type. This
# function, along with 'copy_track', can replace the functionality of
# 'bchunk', if needed. It's able to produce identical CDR files for
# audio tracks. The thing it can't do is turn those files to WAV, so an
# external command (like 'sox') is needed for that.
copy_track_type () {
	track_type="$1"

	declare track_n track_type_ref
	declare -a tracks

# Depending on whether the track type is set to 'all', 'data' or
# 'audio', copy only that type from the source BIN file.
	if [[ $track_type == 'all' ]]; then
		tracks=("${!tracks_type[@]}")
	else
		for (( i = 0; i < ${#tracks_type[@]}; i++ )); do
			track_n=$(( i + 1 ))
			track_type_ref="tracks_type[${track_n}]"

			if [[ ${!track_type_ref} == "$track_type" ]]; then
				tracks+=("$track_n")
			fi
		done
	fi

	if [[ ${#tracks[@]} -eq 0 ]]; then
		return
	fi

	for (( i = 0; i < ${#tracks[@]}; i++ )); do
		track_n="${tracks[${i}]}"
		track_type_ref="tracks_type[${track_n}]"

		copy_track "$track_n" "${!track_type_ref}"
	done

# Creates a file list to be used later in the 'create_cue' function.
	mapfile -t files_cdr < <(get_files "*.bin" "*.cdr")
}

# Creates a function called 'bin_split', which will run 'bchunk' on the
# input file, capture the output, and make a list of all the files
# created.
bin_split () {
	type="$1"

	declare bin_ref args_ref type_tmp exit_status
	declare -a args args_cdr args_wav cmd_stdout

	type_tmp="${audio_types[${type}]}"

	bin_ref="if_cue[1,filename]"

# If WAV files have already been produced, skip this function.
	if [[ $type_tmp == 'wav' && ${#files_wav[@]} -gt 0 ]]; then
		return
	fi

	args=(\""${!bin_ref}"\" \""$cue_tmp"\" \""$of_name"\")

	if [[ $byteswap -eq 1 ]]; then
		args_cdr=(bchunk -s "${args[@]}")
		args_wav=(bchunk -w -s "${args[@]}")
	else
		args_cdr=(bchunk "${args[@]}")
		args_wav=(bchunk -w "${args[@]}")
	fi

	args_ref="args_${type_tmp}[@]"

# Runs 'bchunk', captures the output and saves the exit status in a
# variable, so we can check if errors occurred or not.
	mapfile -t cmd_stdout < <(eval "${!args_ref}" 2>&1; printf '%s\n' "$?")

	exit_status="${cmd_stdout[-1]}"
	unset -v cmd_stdout[-1]

# Prints the output from 'bchunk' if it quits with a non-zero exit
# status.
	if [[ $exit_status != '0' ]]; then
		printf '%s\n' "${cmd_stdout[@]}"
		iquit
	fi

# Creates a file list to be used later in the 'create_cue' function.
	case "$type_tmp" in
		'cdr')
			mapfile -t files_cdr < <(get_files "*.iso" "*.cdr")
		;;
		'wav')
			mapfile -t files_wav < <(get_files "*.iso" "*.wav")
		;;
	esac
}

# Creates a function called 'cdr2wav', which will convert the extracted
# CDR files to WAV (using 'sox'). This function is only run if the
# '-sox' argument has been passed to the script.
cdr2wav () {
	type="$1"

	declare type_tmp
	declare -a files

	type_tmp="${audio_types[${type}]}"

# If WAV files have already been produced or 'type' is not 'wav', skip
# this function.
	if [[ $type_tmp != 'wav' || ${#files_wav[@]} -gt 0 ]]; then
		return
	fi

	mapfile -t files < <(get_files "*.cdr")

	for (( i = 0; i < ${#files[@]}; i++ )); do
		cdr_if="${files[${i}]}"
		cdr_of="${cdr_if%.*}_swapped.cdr"
		wav_of="${cdr_if%.*}.wav"

		declare exit_status
		declare -a args cmd_stdout

		args=(dd conv=swab if=\""${cdr_if}"\" of=\""${cdr_of}"\")

# Makes a temporary byteswapped copy of the CDR file, before running
# 'sox' to convert it to WAV. Otherwise, the the audio will just be
# white noise. Delete the temporary CDR file when done.		
		mapfile -t cmd_stdout < <(eval "${args[@]}" 2>&1; printf '%s\n' "$?")

		exit_status="${cmd_stdout[-1]}"
		unset -v cmd_stdout[-1]

# Prints the output from 'dd' if it quits with a non-zero exit
# status.
		if [[ $exit_status != '0' ]]; then
			printf '%s\n' "${cmd_stdout[@]}"
			iquit
		fi

		sox "$cdr_of" "$wav_of" || iquit
		rm -f "$cdr_of" || iquit

		if [[ -z ${audio_types_run[cdr]} ]]; then
			rm -f "$cdr_if" || iquit
		fi

		unset -v args cmd_stdout exit_status
	done

# Creates a file list to be used later in the 'create_cue' function.
	mapfile -t files_wav < <(get_files "*.bin" "*.wav")
}

# Creates a function called 'encode_audio', which will encode the WAVs
# created by 'bchunk'.
encode_audio () {
	type="$1"

# If there's no WAV files, return from this function. This makes it
# possible for the script to finish normally, even if there's no audio
# tracks.
	if [[ ${#files_wav[@]} -eq 0 ]]; then
		return
	fi

	case "$type" in
		'cdr')
			return
		;;
		'ogg')
			oggenc --quality=10 "${of_dn}"/*.wav || iquit
		;;
		'flac')
			flac -8 "${of_dn}"/*.wav || iquit
		;;
	esac
}

# Creates a function called 'create_cue', which will create a new CUE
# sheet, based on the file lists created by the 'bin_split',
# 'copy_track_type' and 'cdr2wav' functions.
create_cue () {
	type="$1"

	declare type_tmp elements

	type_tmp="${audio_types[${type}]}"

	case "$type_tmp" in
		'cdr')
			elements="${#files_cdr[@]}"
		;;
		'wav')
			elements="${#files_wav[@]}"
		;;
	esac

# Creates a function called 'set_index', which will add the INDEX
# command, and add pregap or postgap, if they exist in the source CUE
# sheet.
	set_index () {
		declare pregap_ref postgap_ref time_tmp

		pregap_ref="gaps[${track_n},pre]"
		postgap_ref="gaps[${track_n},post]"

		if [[ ${!pregap_ref} -gt 0 ]]; then
			time_tmp=$(time_convert "${!pregap_ref}")
			eval of_cue_"${type}"+=\(\""${offset[1]}PREGAP ${time_tmp}"\"\)
		fi

		eval of_cue_"${type}"+=\(\""${offset[1]}${index_default}"\"\)

		if [[ ${!postgap_ref} -gt 0 ]]; then
			time_tmp=$(time_convert "${!postgap_ref}")
			eval of_cue_"${type}"+=\(\""${offset[1]}POSTGAP ${time_tmp}"\"\)
		fi
	}

# Goes through the list of files produced by previously run functions,
# and creates a new CUE sheet based on that.
	for (( i = 0; i < elements; i++ )); do
		line_ref="files_${type_tmp}[${i}]"

		declare fn ext

		if [[ ${!line_ref} =~ ${regex[fn]} ]]; then
			fn="${BASH_REMATCH[1]}"
			ext="${BASH_REMATCH[2]}"
		fi

		track_n=$(( i + 1 ))

		track_mode_ref="if_cue[${track_n},track_mode]"

		track_string=$(printf 'TRACK %02d %s' "$track_n" "${!track_mode_ref}")

		if [[ $ext == 'iso' || $ext == 'bin' ]]; then
			eval of_cue_"${type}"+=\(\""FILE \\\"${fn}.bin\\\" BINARY"\"\)
			eval of_cue_"${type}"+=\(\""${offset[0]}${track_string}"\"\)
			set_index
		else
			case "$type" in
				'cdr')
					of_cue_cdr+=("FILE \"${fn}.cdr\" BINARY")
				;;
				'ogg')
					of_cue_ogg+=("FILE \"${fn}.ogg\" OGG")
				;;
				'flac')
					of_cue_flac+=("FILE \"${fn}.flac\" FLAC")
				;;
			esac
			
			eval of_cue_"${type}"+=\(\""${offset[0]}${track_string}"\"\)
			set_index
		fi

		unset -v fn ext
	done
}

# Creates a function called 'clean_up', which deletes temporary files:
# * ISO file produced by 'bchunk'
# * Potential WAV files
# * Temporary CUE sheet
clean_up () {
	declare -a files

	mapfile -t files < <(get_files "*.iso" "*.wav")

	for (( i = 0; i < ${#files[@]}; i++ )); do
		fn="${files[${i}]}"
		rm -f "$fn" || exit
	done

	rm -f "$cue_tmp" || exit
}

# Checks if 'oggenc', 'flac' are installed. Depending on which mode is
# set, check if 'bchunk' or 'sox' is installed.
check_cmd 'oggenc' 'flac' "$mode"

# Creates the output directory and changes into it.
mkdir "$of_dn" || exit
cd "$of_dn" || exit

# Runs the functions.
read_cue
loop_set

if [[ $mode == 'sox' ]]; then
	copy_track_type 'all'
fi

for type in "${!audio_types_run[@]}"; do
	if [[ $mode == 'bchunk' ]]; then
		bin_split "$type"
	fi

	if [[ $mode == 'sox' ]]; then
		cdr2wav "$type"
	fi

	encode_audio "$type"
	create_cue "$type"
done

# Prints the created CUE sheet to the terminal, and to the output file.
for type in "${!audio_types_run[@]}"; do
	of_cue="${of_dn}/${of_name}01_${type}.cue"
	lines_ref="of_cue_${type}[@]"

	printf '\n'
	printf '%s\r\n' "${!lines_ref}" | tee "$of_cue"
done

printf '\n' 

# Deletes temporary files.
clean_up

# Copies data track(s) from source BIN file.
if [[ $mode == 'bchunk' ]]; then
	copy_track_type 'data'
fi
