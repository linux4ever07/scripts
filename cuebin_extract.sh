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
# 3 formats, and create CUE files for all 3 formats as well.

# The purpose of the script is to take DOS games that have CD Audio,
# and getting rid of the need to store the uncompressed CD Audio. Ogg
# Vorbis is a lossy codec, so the files are much smaller and near the
# same quality. In the case of FLAC, it's a lossless format so the
# quality is identical to native CD audio. The only difference is FLAC
# is losslessly compressed so the files are slightly smaller. The
# generated CUE files can be used with DOSBox, using the 'IMGMOUNT'
# command.

# https://www.dosbox.com/wiki/IMGMOUNT

# It's also possible to do a byteswap on the audio tracks (to switch the
# endianness / byte order), through the optional '-byteswap' argument.
# This is needed in some cases to burn games, or the audio tracks will
# be white noise if the endianness is wrong. So, it's easy to tell
# whether or not the byte order is correct.

# The ISO file produced by 'bchunk' is discarded, and the data track is
# instead copied directly from the original BIN file, calculating the
# length of the data track based on the information gathered from the
# CUE file.

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

audio_types=(['cdr']=0 ['ogg']=0 ['flac']=0)
exclusive=0
byteswap=0

# The loop below handles the arguments to the script.
shift

while [[ $# -gt 0 ]]; do
	case "$1" in
		'-cdr')
			audio_types['cdr']=1
			exclusive=1

			shift
		;;
		'-ogg')
			audio_types['ogg']=1
			exclusive=1

			shift
		;;
		'-flac')
			audio_types['flac']=1
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
	audio_types=(['cdr']=1 ['ogg']=1 ['flac']=1)
fi

session="${RANDOM}-${RANDOM}"

if_name="${if_bn_lc%.[^.]*}"
of_name=$(tr '[:blank:]' '_' <<<"$if_name")

if_dn=$(dirname "$if")
of_dn="${PWD}/${of_name}-${session}"

of_cdr_cue="${of_dn}/${of_name}01_cdr.cue"
of_ogg_cue="${of_dn}/${of_name}01_ogg.cue"
of_flac_cue="${of_dn}/${of_name}01_flac.cue"

of_bin="${of_dn}/${of_name}01.bin"
of_iso="${of_dn}/${of_name}01.iso"

cue="$if"
cue_tmp_f="/dev/shm/${of_name}-${session}.cue"
bin=$(find "$if_dn" -maxdepth 1 -type f -iname "${if_name}.bin" 2>&- | head -n 1)

declare -a format offset

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

regex_bchunk='^ *[0-9]+: (.*\.[[:alpha:]]{3}).*$'
regex_iso='\.iso$'
regex_wav='\.wav$'

index1='INDEX 01 00:00:00'
offset=('  ' '    ')

declare -A cue_lines
declare -a bchunk_cdr_list bchunk_wav_list of_cue_cdr_list of_cue_ogg_list of_cue_flac_list

# trap ctrl-c and call ctrl_c()
trap ctrl_c INT

ctrl_c () {
	printf '%s\n' '** Trapped CTRL-C'
	rm -f "$cue_tmp_f"
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
# file, add full path to filenames listed in the CUE file, and create a
# new temporary CUE file in /dev/shm based on this.
read_cue () {
	declare -a files not_found cue_tmp

	track_n=0

	handle_command () {
# If line is a file command...
		if [[ $1 =~ ${format[3]} ]]; then
			match=("${BASH_REMATCH[@]:1}")
			track_n=$(( track_n + 1 ))
			fn=$(tr -d '"' <<<"${match[1]}" | sed -E "s/${regex_path}//")

			fn_found=$(find "$if_dn" -maxdepth 1 -type f -iname "$fn" 2>&- | head -n 1)

			if [[ -f $fn_found ]]; then
				fn="$fn_found"
			else
				not_found+=("$fn")

				if [[ $track_n -eq 1 && -f $bin ]]; then
					fn="$bin"
				fi
			fi

			files+=("$fn")

			string="${match[0]} \"${fn}\" ${match[2]}"

			cue_lines["${track_n},file"]="$string"
		fi

# If line is a track command...
		if [[ $1 =~ ${format[4]} ]]; then
			match=("${BASH_REMATCH[@]:1}")
			track_n="${match[1]#0}"

			string="$1"

			cue_lines["${track_n},track"]="$string"
		fi

# If line is a pregap command...
		if [[ $1 =~ ${format[5]} ]]; then
			match=("${BASH_REMATCH[@]:1}")

			string="$1"

			cue_lines["${track_n},pregap"]="$string"
		fi

# If line is an index command...
		if [[ $1 =~ ${format[6]} ]]; then
			match=("${BASH_REMATCH[@]:1}")
			index_n="${match[1]#0}"

			string="$1"

			cue_lines["${track_n},index,${index_n}"]="$string"
		fi

# If line is a postgap command...
		if [[ $1 =~ ${format[7]} ]]; then
			match=("${BASH_REMATCH[@]:1}")

			string="$1"

			cue_lines["${track_n},postgap"]="$string"
		fi

# If a string has been created, add it to the 'cue_tmp' array.
		if [[ -n $string ]]; then
			cue_tmp+=("$string")
		fi
	}

	mapfile -t cue_lines_if < <(tr -d '\r' <"$cue" | sed -E "s/${regex_blank}/\1/")

	for (( i=0; i<${#cue_lines_if[@]}; i++ )); do
		line="${cue_lines_if[${i}]}"

		handle_command "$line"
	done

	if [[ ${#files[@]} -gt 1 ]]; then
		cat <<MERGE

This CUE file contains multiple FILE commands!

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

	printf '%s\n' "${cue_tmp[@]}" > "$cue_tmp_f"
}

# Creates a function called 'bin_split', which will run 'bchunk' on the
# input file, capture the output, and make a list of all the files
# created.
bin_split () {
	type="$1"

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

	args_tmp=(\""$bin"\" \""$cue_tmp_f"\" \""$of_name"\")

	n=0

	if [[ $byteswap -eq 1 ]]; then
		cdr_args=(bchunk -s "${args_tmp[@]}")
		wav_args=(bchunk -w -s "${args_tmp[@]}")
	else
		cdr_args=(bchunk "${args_tmp[@]}")
		wav_args=(bchunk -w "${args_tmp[@]}")
	fi

	case "$type_tmp" in
		'cdr')
			mapfile -t bchunk_cdr_stdout < <(eval "${cdr_args[@]}"; printf '%s\n' "$?")
			elements="${#bchunk_cdr_stdout[@]}"
		;;
		'wav')
# If WAV files have already been produced, skip this function.
			if [[ ${#bchunk_wav_stdout[@]} -gt 0 ]]; then
				return
			fi

			mapfile -t bchunk_wav_stdout < <(eval "${wav_args[@]}"; printf '%s\n' "$?")
			elements="${#bchunk_wav_stdout[@]}"
		;;
	esac

	last=$(( elements - 1 ))

	exit_status_ref="bchunk_${type_tmp}_stdout[-1]"

# Print the output from 'bchunk' if it quits with a non-zero exit
# status.
	if [[ ${!exit_status_ref} != '0' ]]; then
		for (( i=0; i<last; i++ )); do
			bchunk_stdout_ref="bchunk_${type_tmp}_stdout[${i}]"

			printf '%s\n' "${!bchunk_stdout_ref}"
		done

		exit
	fi

	for (( i=0; i<last; i++ )); do
		line_ref="bchunk_${type_tmp}_stdout[${i}]"

		if [[ ${!line_ref} == 'Writing tracks:' ]]; then
			n=$(( i + 2 ))
			break
		fi
	done

	for (( i=n; i<last; i++ )); do
		bchunk_stdout_ref="bchunk_${type_tmp}_stdout[${i}]"
		line=$(sed -E "s/${regex_bchunk}/\1/" <<<"${!bchunk_stdout_ref}")

		case "$type_tmp" in
			'cdr')
				bchunk_cdr_list+=("$line")
			;;
			'wav')
				bchunk_wav_list+=("$line")
			;;
		esac
	done
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
			oggenc --quality=10 "${of_dn}"/*.wav || exit
		;;
		'flac')
			flac -8 "${of_dn}"/*.wav || exit
		;;
	esac
}

# Creates a function called 'create_cue', which will create a new CUE
# file, based on the file list created by the 'bin_split' function.
create_cue () {
	type="$1"

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
			elements="${#bchunk_cdr_list[@]}"
		;;
		'wav')
			elements="${#bchunk_wav_list[@]}"
		;;
	esac

# Creates a function called 'add_gap', which will add pregap or postgap,
# if they exist in the source CUE file.
	add_gap () {
		case "$1" in
			'pre')
				string="${cue_lines[${track_n},pregap]}"

				if [[ -n $string ]]; then
					eval of_cue_"${type}"_list+=\(\""${offset[1]}${string}"\"\)
				fi

# If the original CUE specifies a pregap using the INDEX command,
# convert that to a PREGAP command.
				index_00="${cue_lines[${track_n},index,0]}"
				index_01="${cue_lines[${track_n},index,1]}"

				if [[ -n $index_00 && -n $index_01 ]]; then
					index_00=$(sed -E "s/${format[6]}/\3/" <<<"$index_00")
					index_01=$(sed -E "s/${format[6]}/\3/" <<<"$index_01")

					index_00_frames=$(time_convert "$index_00")
					index_01_frames=$(time_convert "$index_01")

					if [[ $index_01_frames -gt $index_00_frames ]]; then
						frames_diff=$(( index_01_frames - index_00_frames ))
						time_diff=$(time_convert "$frames_diff")

						eval of_cue_"${type}"_list+=\(\""${offset[1]}PREGAP ${time_diff}"\"\)
					fi
				fi
			;;
			'post')
				string="${cue_lines[${track_n},postgap]}"

				if [[ -n $string ]]; then
					eval of_cue_"${type}"_list+=\(\""${offset[1]}${string}"\"\)
				fi
			;;
		esac
	}

	for (( i=0; i<elements; i++ )); do
		line_ref="bchunk_${type_tmp}_list[${i}]"

		track_n=$(( i + 1 ))

		if [[ ${!line_ref} =~ $regex_iso ]]; then
			eval of_cue_"${type}"_list+=\(\""FILE \\\"${!line_ref%.iso}.bin\\\" BINARY"\"\)
			eval of_cue_"${type}"_list+=\(\""${offset[0]}${cue_lines[${track_n},track]}"\"\)
			add_gap pre
			eval of_cue_"${type}"_list+=\(\""${offset[1]}${index1}"\"\)
			add_gap post
		else
			case "$type" in
				'cdr')
					of_cue_cdr_list+=("FILE \"${!line_ref}\" BINARY")
				;;
				'ogg')
					of_cue_ogg_list+=("FILE \"${!line_ref%.wav}.ogg\" OGG")
				;;
				'flac')
					of_cue_flac_list+=("FILE \"${!line_ref%.wav}.flac\" FLAC")
				;;
			esac

			string=$(printf 'TRACK %02d AUDIO' "$track_n")
			
			eval of_cue_"${type}"_list+=\(\""${offset[0]}${string}"\"\)
			add_gap pre
			eval of_cue_"${type}"_list+=\(\""${offset[1]}${index1}"\"\)
			add_gap post
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

# Creates a function called 'data_track', which copies the raw binary
# data from the original BIN file for the data track.
data_track () {
	sector=('2048' '2352')

	declare string

	if [[ -n ${cue_lines[2,index,0]} ]]; then
		string="${cue_lines[2,index,0]}"
	else
		string="${cue_lines[2,index,1]}"
	fi

	if [[ -z $string ]]; then
		return
	fi

	time=$(sed -E "s/${format[6]}/\3/" <<<"$string")
	frames=$(time_convert "$time")

# 2048 bytes is normally the sector size for data CDs / tracks, and 2352
# bytes is the size of audio sectors.
	dd if="$bin" of="$of_bin" bs="${sector[1]}" count="$frames"
}

# Creates a function called 'clean_up', which deletes temporary files,
# meaning potential WAV files, the ISO file produced by 'bchunk'
# and the temporary CUE file.
clean_up () {
	mapfile -t files < <(find "$of_dn" -maxdepth 1 -type f -iname "*.wav" 2>&-)

	for (( i=0; i<${#files[@]}; i++ )); do
		fn="${files[${i}]}"
		rm -f "$fn" || exit
	done

	rm -f "$of_iso" "$cue_tmp_f" || exit
}

# Check if 'oggenc', 'flac' and 'bchunk' are installed.
check_cmd oggenc flac bchunk

# Create the output directory and change into it.
mkdir "$of_dn" || exit
cd "$of_dn" || exit

# Run the functions.
read_cue

for type in "${!audio_types[@]}"; do
	if [[ ${audio_types[${type}]} -eq 0 ]]; then
		continue
	fi

	bin_split "$type"
	encode_audio "$type"
	create_cue "$type"
done

printf '\n'

# Print the created CUE file to the terminal, and to the output file.
for type in "${!audio_types[@]}"; do
	if [[ ${audio_types[${type}]} -eq 0 ]]; then
		continue
	fi

	of_cue_ref="of_${type}_cue"

	lines_ref="of_cue_${type}_list[@]"
	printf '%s\r\n' "${!lines_ref}" | tee "${!of_cue_ref}"

	printf '\n'
done

printf '\n' 

# Delete temporary files.
clean_up

# Copy data track from original BIN file.
data_track
