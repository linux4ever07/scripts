#!/bin/bash

# This script is meant to take an input BIN/CUE file, extract the raw
# data track, as well as audio tracks in whatever format the user has
# specified through script arguments. The script simply separates all
# the tracks (data / audio) of BIN/CUE files.

# Available audio formats are:
# * cdr (native CD audio)
# * ogg (Ogg Vorbis)
# * flac (Free Lossless Audio Codec)

# If no format is specified as an argument, the script will extract all
# 3 formats, and create CUE sheets for all 3 formats as well.

# The purpose of the script is to take DOS games that have CD Audio,
# and getting rid of the need to store the uncompressed CD Audio. Ogg
# Vorbis is a lossy codec, so the files are much smaller and near the
# same quality. In the case of FLAC, it's a lossless format so the
# quality is identical to native CD audio. The only difference is FLAC
# is losslessly compressed so the files are slightly smaller. The
# generated CUE sheets can be used with DOSBox, using the 'IMGMOUNT'
# command.

# https://www.dosbox.com/wiki/IMGMOUNT

# Another use case for this script is to simply extract the OST from
# games, to listen to.

# It's possible to do a byteswap on the audio tracks (to switch the
# endianness / byte order), through the optional '-byteswap' argument.
# This is needed in some cases to burn games, or the audio tracks will
# be white noise if the endianness is wrong. So, it's easy to tell
# whether or not the byte order is correct.

# The ISO file produced by 'bchunk' is discarded, and the data track is
# instead copied directly from the original BIN file, calculating the
# length of the data track based on the information gathered from the
# CUE sheet.

# Since the 'copy_track' function is now able to correctly copy any
# track from the original BIN file, it may be possible to make this
# script not depend on 'bchunk' anymore.

# 'sox' is able to convert the resulting BIN files to WAV without using
# 'bchunk' (if the BIN files have the '.cdr' extension), and the
# byteswap can be done with 'dd':

# sox in.cdr out.wav
# dd conv=swab if=in.cdr of=out.cdr

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

declare -A audio_types

audio_types=([cdr]=0 [ogg]=0 [flac]=0)
exclusive=0
byteswap=0

# The loop below handles the arguments to the script.
shift

while [[ $# -gt 0 ]]; do
	case "$1" in
		'-cdr')
			audio_types[cdr]=1
			exclusive=1

			shift
		;;
		'-ogg')
			audio_types[ogg]=1
			exclusive=1

			shift
		;;
		'-flac')
			audio_types[flac]=1
			exclusive=1

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

if [[ $exclusive -eq 0 ]]; then
	audio_types=([cdr]=1 [ogg]=1 [flac]=1)
fi

session="${RANDOM}-${RANDOM}"

if_name="${if_bn_lc%.[^.]*}"
of_name=$(tr '[:blank:]' '_' <<<"$if_name")

if_dn=$(dirname "$if")
of_dn="${PWD}/${of_name}-${session}"

cue="$if"
cue_tmp="/dev/shm/${of_name}-${session}.cue"
bin=$(find "$if_dn" -maxdepth 1 -type f -iname "${if_name}.bin" 2>&- | head -n 1)

declare -A regex
declare -a format offset

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

regex[data]='^MODE[0-9]+/[0-9]+$'
regex[audio]='^AUDIO$'

regex[bchunk]='^ *[0-9]+: (.*\.[[:alpha:]]{3}).*$'
regex[iso]='\.iso$'
regex[wav]='\.wav$'

index_default='INDEX 01 00:00:00'
offset=('  ' '    ')

declare -A if_cue gaps
declare -a frames bchunk_cdr bchunk_wav of_cue_cdr of_cue_ogg of_cue_flac

# trap ctrl-c and call ctrl_c()
trap ctrl_c INT

ctrl_c () {
	printf '%s\n' '** Trapped CTRL-C'
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

# Creates a function called 'read_cue', which will read the input CUE
# sheet, add full path to file names listed in the CUE sheet, and create
# a new temporary CUE sheet in /dev/shm based on this.
read_cue () {
	declare -a files not_found lines lines_tmp

	track_n=0

	handle_command () {
# If line is a file command...
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

# If line is a track command...
		if [[ $1 =~ ${format[4]} ]]; then
			match=("${BASH_REMATCH[@]:1}")
			track_n="${match[1]#0}"

			string="$1"

			if_cue["${track_n},track_number"]="${match[1]}"
			if_cue["${track_n},track_mode"]="${match[2]}"
		fi

# If line is a pregap command...
		if [[ $1 =~ ${format[5]} ]]; then
			match=("${BASH_REMATCH[@]:1}")

			string="$1"

			if_cue["${track_n},pregap"]="${match[1]}"
		fi

# If line is an index command...
		if [[ $1 =~ ${format[6]} ]]; then
			match=("${BASH_REMATCH[@]:1}")
			index_n="${match[1]#0}"

			string="$1"

			if_cue["${track_n},index,${index_n}"]="${match[2]}"
		fi

# If line is a postgap command...
		if [[ $1 =~ ${format[7]} ]]; then
			match=("${BASH_REMATCH[@]:1}")

			string="$1"

			if_cue["${track_n},postgap"]="${match[1]}"
		fi

# If a string has been created, add it to the 'lines_tmp' array.
		if [[ -n $string ]]; then
			lines_tmp+=("$string")
		fi
	}

	mapfile -t lines < <(tr -d '\r' <"$cue" | sed -E "s/${regex[blank]}/\1/")

	for (( i = 0; i < ${#lines[@]}; i++ )); do
		line="${lines[${i}]}"
		handle_command "$line"
	done

	if [[ ${#files[@]} -gt 1 ]]; then
		cat <<MERGE

This CUE sheet contains multiple FILE commands!

You need to merge all the containing files into one BIN file, using a
tool like PowerISO.

MERGE

		exit
	fi

	if [[ ${#not_found[@]} -gt 0 ]]; then
		printf '\n%s\n\n' 'The files below were not found:'

		printf '%s\n' "${not_found[@]}"

		printf '\n'
	fi

	printf '%s\n' "${lines_tmp[@]}" > "$cue_tmp"
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

# Creates a function called 'get_frames', which will get the position of
# a track in the BIN file.
get_frames () {
	track_n="$1"

	declare index_0_ref index_1_ref index_ref frames_tmp

	index_0_ref="if_cue[${track_n},index,0]"
	index_1_ref="if_cue[${track_n},index,1]"

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
	declare frames_this frames_next

	i=0

	while [[ 1 ]]; do
		i=$(( i + 1 ))
		j=$(( i + 1 ))
		frames_this=$(get_frames "$i")
		frames_next=$(get_frames "$j")

		if [[ -n $frames_next ]]; then
			frames["${i}"]=$(( frames_next - frames_this ))
		else
			break
		fi
	done
}

# Creates a function called 'get_gaps', which will get pregaps and
# postgaps from the CUE sheet for the track number given as argument.
# If there's both a pregap specified using the PREGAP command and INDEX
# command, those values will be added together. However, a CUE sheet is
# highly unlikely to specify a pregap twice like that.
get_gaps () {
	track_n="$1"

	declare index_0 index_0_ref index_1 index_1_ref frames_tmp

	pregap=0
	postgap=0

# If the CUE sheet specifies a pregap using the INDEX command, convert
# that to a PREGAP command.
	index_0_ref="if_cue[${track_n},index,0]"
	index_1_ref="if_cue[${track_n},index,1]"

	if [[ -n ${!index_0_ref} && -n ${!index_1_ref} ]]; then
		index_0=$(time_convert "${!index_0_ref}")
		index_1=$(time_convert "${!index_1_ref}")

		if [[ $index_1 -gt $index_0 ]]; then
			frames_tmp=$(( index_1 - index_0 ))
			pregap=$(( pregap + frames_tmp ))
			gaps["${track_n},index"]="$frames_tmp"
		fi
	fi

	pregap_ref="if_cue[${track_n},pregap]"
	postgap_ref="if_cue[${track_n},postgap]"

	if [[ -n ${!pregap_ref} ]]; then
		frames_tmp=$(time_convert "${!pregap_ref}")
		pregap=$(( pregap + frames_tmp ))
	fi

	if [[ -n ${!postgap_ref} ]]; then
		frames_tmp=$(time_convert "${!postgap_ref}")
		postgap=$(( postgap + frames_tmp ))
	fi

	gaps["${track_n},pre"]="$pregap"
	gaps["${track_n},post"]="$postgap"
}

# Creates a function called 'set_gaps', which will get pregaps and
# postgaps for all tracks in the BIN file.
set_gaps () {
	declare track_ref

	i=0

	while [[ 1 ]]; do
		i=$(( i + 1 ))
		track_ref="if_cue[${i},track_number]"

		if [[ -n ${!track_ref} ]]; then
			get_gaps "$i"
		else
			break
		fi
	done
}

# Creates a function called 'copy_track', which will extract the raw
# binary data for the track number given as argument, from the BIN file.
copy_track () {
	track_n="$1"
	track_type="$2"

	declare ext frames_ref gaps_ref count skip
	declare -a sector args

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

# 2048 bytes is normally the sector size for data CDs / tracks, and 2352
# bytes is the size of audio sectors.
	sector=('2048' '2352')

# Creates the first part of the 'dd' command.
	args=(dd if=\""${bin}"\" of=\""${of_bin}"\" bs=\""${sector[1]}"\")

# Gets the length of the track, unless it's the last track, in which
# case the length will be absent from the 'frames' array.
	frames_ref="frames[${track_n}]"
	gaps_ref="gaps[${track_n},index]"

	if [[ -n ${!frames_ref} ]]; then
		count="${!frames_ref}"

		if [[ -n ${!gaps_ref} ]]; then
			count=$(( count - ${!gaps_ref} ))
		fi

		args+=(count=\""${count}"\")
	fi

	skip=0

# If there's a pregap in the CUE sheet specified by an INDEX command,
# that means the gap is present in the BIN file itself, so we skip that
# part.
	if [[ -n ${!gaps_ref} ]]; then
		skip=$(( skip + ${!gaps_ref} ))
	fi

# If the track number is higher than '1', figure out how many frames to
# skip when reading the BIN file.
	if [[ $track_n -gt 1 ]]; then
		for (( i = 1; i < track_n; i++ )); do
			skip=$(( skip + ${frames[${i}]} ))
		done
	fi

	if [[ $skip -gt 0 ]]; then
		args+=(skip=\""${skip}"\")
	fi

# Runs 'dd'.
	eval "${args[@]}"
}

# Creates a function called 'copy_track_type', which will extract the
# raw binary data for all tracks of either the data or audio type. This
# function, along with 'copy_track', can replace the functionality of
# 'bchunk', if needed. It's able to produce identical CDR files for
# audio tracks. The thing it can't do is turn those files to WAV, so an
# external command (like 'sox') is needed for that.
copy_track_type () {
	track_type="$1"

	declare track_mode_ref tracks_ref elements
	declare -a data_tracks audio_tracks

	i=0

# Loops through all the track modes, to figure out which tracks are
# data, and which are audio.
	while [[ 1 ]]; do
		i=$(( i + 1 ))
		track_mode_ref="if_cue[${i},track_mode]"

		if [[ -n ${!track_mode_ref} ]]; then
			if [[ ${!track_mode_ref} =~ ${regex[data]} ]]; then
				data_tracks+=("$i")
				continue
			fi

			if [[ ${!track_mode_ref} =~ ${regex[audio]} ]]; then
				audio_tracks+=("$i")
				continue
			fi
		else
			break
		fi
	done

	elements=0

	case "$track_type" in
		'data')
			tracks_ref='data_tracks[@]'
			elements="${#data_tracks[@]}"
		;;
		'audio')
			tracks_ref='audio_tracks[@]'
			elements="${#audio_tracks[@]}"
		;;
	esac

	if [[ $elements -eq 0 ]]; then
		return
	fi

	for track_n in "${!tracks_ref}"; do
		copy_track "$track_n" "$track_type"
	done
}

# Creates a function called 'bin_split', which will run 'bchunk' on the
# input file, capture the output, and make a list of all the files
# created.
bin_split () {
	type="$1"

	declare type_tmp args_ref bchunk_stdout exit_status
	declare -a args args_cdr args_wav files

	case "$type" in
		'cdr')
			type_tmp='cdr'
		;;
		'ogg')
			type_tmp='wav'
		;;
		'flac')
			type_tmp='wav'
		;;
	esac

# If WAV files have already been produced, skip this function.
	if [[ $type_tmp == 'wav' && ${#bchunk_wav[@]} -gt 0 ]]; then
		return
	fi

	args=(\""$bin"\" \""$cue_tmp"\" \""$of_name"\")

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
	mapfile -t bchunk_stdout < <(eval "${!args_ref}"; printf '%s\n' "$?")

	exit_status="${bchunk_stdout[-1]}"
	unset -v bchunk_stdout[-1]

# Prints the output from 'bchunk' if it quits with a non-zero exit
# status.
	if [[ $exit_status != '0' ]]; then
		printf '%s\n' "${bchunk_stdout[@]}"
		rm -f "$cue_tmp"
		exit
	fi

	n=0

	for (( i = 0; i < ${#bchunk_stdout[@]}; i++ )); do
		line="${bchunk_stdout[${i}]}"

		if [[ $line == 'Writing tracks:' ]]; then
			n=$(( i + 2 ))
			break
		fi
	done

# Saves the list of files produced by 'bchunk' in the 'files' array.
	for (( i = n; i < ${#bchunk_stdout[@]}; i++ )); do
		line="${bchunk_stdout[${i}]}"

		if [[ $line =~ ${regex[bchunk]} ]]; then
			files+=("${BASH_REMATCH[1]}")
		fi
	done

	case "$type_tmp" in
		'cdr')
			bchunk_cdr=("${files[@]}")
		;;
		'wav')
			bchunk_wav=("${files[@]}")
		;;
	esac
}

# Creates a function called 'encode_audio', which will encode the WAVs
# created by 'bchunk'.
encode_audio () {
	type="$1"

	case "$type" in
		'cdr')
			return
		;;
		'ogg')
			oggenc --quality=10 "${of_dn}"/*.wav
		;;
		'flac')
			flac -8 "${of_dn}"/*.wav
		;;
	esac

	if [[ $? -ne 0 ]]; then
		rm -f "$cue_tmp"
		exit
	fi
}

# Creates a function called 'create_cue', which will create a new CUE
# sheet, based on the file list created by the 'bin_split' function.
create_cue () {
	type="$1"

	declare type_tmp elements

	case "$type" in
		'cdr')
			type_tmp='cdr'
		;;
		'ogg')
			type_tmp='wav'
		;;
		'flac')
			type_tmp='wav'
		;;
	esac

	case "$type_tmp" in
		'cdr')
			elements="${#bchunk_cdr[@]}"
		;;
		'wav')
			elements="${#bchunk_wav[@]}"
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

	for (( i = 0; i < elements; i++ )); do
		line_ref="bchunk_${type_tmp}[${i}]"

		track_n=$(( i + 1 ))
		track_mode_ref="if_cue[${track_n},track_mode]"
		track_string=$(printf 'TRACK %02d %s' "$track_n" "${!track_mode_ref}")

		if [[ ${!line_ref} =~ ${regex[iso]} ]]; then
			eval of_cue_"${type}"+=\(\""FILE \\\"${!line_ref%.iso}.bin\\\" BINARY"\"\)
			eval of_cue_"${type}"+=\(\""${offset[0]}${track_string}"\"\)
			set_index
		else
			case "$type" in
				'cdr')
					of_cue_cdr+=("FILE \"${!line_ref}\" BINARY")
				;;
				'ogg')
					of_cue_ogg+=("FILE \"${!line_ref%.wav}.ogg\" OGG")
				;;
				'flac')
					of_cue_flac+=("FILE \"${!line_ref%.wav}.flac\" FLAC")
				;;
			esac
			
			eval of_cue_"${type}"+=\(\""${offset[0]}${track_string}"\"\)
			set_index
		fi
	done
}

# Creates a function called 'clean_up', which deletes temporary files:
# * ISO file produced by 'bchunk'
# * Potential WAV files
# * Temporary CUE sheet
clean_up () {
	mapfile -t files < <(find "$of_dn" -maxdepth 1 -type f \( -iname "*.iso" -o -iname "*.wav" \) 2>&-)

	for (( i = 0; i < ${#files[@]}; i++ )); do
		fn="${files[${i}]}"
		rm -f "$fn" || exit
	done

	rm -f "$cue_tmp" || exit
}

# Checks if 'oggenc', 'flac' and 'bchunk' are installed.
check_cmd oggenc flac bchunk

# Creates the output directory and change into it.
mkdir "$of_dn" || exit
cd "$of_dn" || exit

# Runs the functions.
read_cue
set_frames
set_gaps

for type in "${!audio_types[@]}"; do
	if [[ ${audio_types[${type}]} -eq 0 ]]; then
		continue
	fi

	bin_split "$type"
	encode_audio "$type"
	create_cue "$type"
done

printf '\n'

# Prints the created CUE sheet to the terminal, and to the output file.
for type in "${!audio_types[@]}"; do
	if [[ ${audio_types[${type}]} -eq 0 ]]; then
		continue
	fi

	of_cue="${of_dn}/${of_name}01_${type}.cue"

	lines_ref="of_cue_${type}[@]"
	printf '%s\r\n' "${!lines_ref}" | tee "$of_cue"

	printf '\n'
done

printf '\n' 

# Deletes temporary files.
clean_up

# Copies data track(s) from original BIN file.
copy_track_type 'data'
