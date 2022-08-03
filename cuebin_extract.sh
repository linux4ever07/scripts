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

session="${RANDOM}-${RANDOM}"

# Creates a function called 'usage', which will print usage and quit.
usage () {
	cat <<USAGE

Usage: $(basename "$0") [CUE] [...]

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

declare -A audio_types

audio_types=(['cdr']=0 ['ogg']=0 ['flac']=0)
exclusive=0
byteswap=0

# The loop below handles the arguments to the script.
shift

while [[ -n $@ ]]; do
	case $1 in
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

if_bn=$(basename "$if")
if_bn_lc=$(tr '[:upper:]' '[:lower:]' <<<"$if_bn")

# If $if is not a real file, or it has the wrong extension, print usage
# and quit.
if [[ ! -f $if || ${if_bn_lc##*.} != 'cue' ]]; then
	usage
fi

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
cue_tmp_f="/dev/shm/${if_bn%.[^.]*}-${session}.cue"
bin=$(find "$if_dn" -maxdepth 1 -iname "${if_name}.bin" | head -n 1)

regex_blank='^[[:blank:]]*(.*)[[:blank:]]*$'
regex_fn='^FILE \"{0,1}(.*\/){0,1}(.*)\"{0,1} (.*)$'
regex_bchunk='^ *[0-9]+: (.*\.[[:alpha:]]{3}).*$'
regex_frames='[0-9]+'
regex_time='[0-9]{2}:[0-9]{2}:[0-9]{2}'
regex_audio='^TRACK [0-9]{2,} AUDIO$'
regex_index="^INDEX ([0-9]{2,}) (${regex_time})$"
regex_mode='^TRACK [0-9]{2,} MODE'
regex_iso='\.iso$'
regex_wav='\.wav$'

declare -A gaps
declare -a cue_lines bchunk_cdr_list bchunk_wav_list of_cue_cdr_list of_cue_ogg_list of_cue_flac_list modes

# trap ctrl-c and call ctrl_c()
trap ctrl_c INT

ctrl_c () {
	rm -f "$cue_tmp_f"
	printf '%s\n' '** Trapped CTRL-C'
	exit
}

# Creates a function called 'check_cmd', which will check if the
# necessary commands are installed.
check_cmd () {
	for cmd in "$@"; do
		command -v "$cmd" 1>&- 2>&-

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
	mapfile -t cue_lines < <(tr -d '\r' <"$cue" | sed -E "s/${regex_blank}/\1/")

	declare -a bin_list not_found

	n='0'

	touch "$cue_tmp_f"

	for (( i=0; i<${#cue_lines[@]}; i++ )); do
		cue_lines[${i}]="${cue_lines[${i}]}"

		if [[ ${cue_lines[${i}]} =~ $regex_fn ]]; then
			n=$(( n + 1 ))

# Extracting the filename from line, and removing path from it.
			bin_tmp=$(sed -E "s/${regex_fn}/\2/" <<<"${cue_lines[${i}]}")
			bin_tmp=$(tr -d '"' <<<"$bin_tmp")

# Adding the full path to filename.
			bin_tmp="${if_dn}/${bin_tmp}"
			bin_list+=("$bin_tmp")

# If $bin isn't set, set it. That means that the find command in the
# beginning of the script didn't find a BIN file, but now we've found it
# by parsing the input CUE file.
# If the number of FILE commands is greater than 1, quit.
			if [[ -z $bin ]]; then
				bin="$bin_tmp"
			fi
			if [[ $n -gt 1 ]]; then
				printf '\n%s\n' 'This CUE file contains multiple FILE commands!'
				printf '%s\n\n' 'You need to merge all the containing files into one BIN file, using a tool like PowerISO.'
				rm -f "$cue_tmp_f"
				exit
			fi

# Getting the filetype information from line, and replacing line with a
# new one containing the full path to file. We need this, since we're
# creating a temporary input CUE file in /dev/shm, so its location will
# be different from the files it points to.
			f_type=$(sed -E "s/${regex_fn}/\3/" <<<"${cue_lines[${i}]}")
			cue_lines[${i}]="FILE \"${bin_tmp}\" ${f_type}"
		fi

		printf '%s\n' "${cue_lines[${i}]}" >> "$cue_tmp_f"
	done

# If the filenames in the CUE aren't real files, then print the
# filenames and quit.
	for (( i=0; i<${#bin_list[@]}; i++ )); do
		if [[ ! -f ${bin_list[${i}]} ]]; then
			not_found+=("${bin_list[${i}]}")
		fi
	done

	if [[ -n ${not_found[@]} ]]; then
		printf '\n%s\n\n' 'The files below were not found:'

		for (( i=0; i<${#not_found[@]}; i++ )); do
			printf '%s\n' "${not_found[${i}]}"
		done

		printf '\n' 

		rm -f "$cue_tmp_f"
		exit
	fi

	n=0

# The loop below adds MODE, PREGAP and POSTGAP commands to be processed
# later by the 'create_cue' function.
	for (( i=0; i<${#cue_lines[@]}; i++ )); do
		line="${cue_lines[${i}]}"

		case $line in
			'TRACK'*)
				n=$(( n + 1 ))

# If line contains a MODE command, save it for later to be added by the
# 'create_cue" function.
				if [[ $line =~ $regex_mode ]]; then
					modes[${n}]="$line"
				fi

				next=$(( i + 1 ))
				line_next="${cue_lines[${next}]}"
				next=$(( i + 2 ))
				line_next_2="${cue_lines[${next}]}"

				if [[ $line_next =~ $regex_index && $line_next_2 =~ $regex_index ]]; then
# If the original CUE specifies a pregap using the INDEX command,
# convert that to a PREGAP command.
					index_n=$(sed -E "s/${regex_index}/\1/" <<<"$line_next")
					index_next_n=$(sed -E "s/${regex_index}/\1/" <<<"$line_next_2")

					if [[ $index_n == '00' && $index_next_n == '01' ]]; then
						time_index=$(sed -E "s/${regex_index}/\2/" <<<"$line_next")
						time_index_next=$(sed -E "s/${regex_index}/\2/" <<<"$line_next_2")
						frames=$(time_convert "$time_index")
						frames_next=$(time_convert "$time_index_next")

						if [[ $frames_next -gt $frames ]]; then
							frames_diff=$(( $frames_next - $frames ))

							time_diff=$(time_convert "$frames_diff")

							if [[ -z ${gaps[pre,${n}]} ]]; then
								gaps[pre,${n}]="PREGAP ${time_diff}"
							fi
						fi
					fi
				fi
			;;
			'PREGAP'*)
				gaps[pre,${n}]="$line"
			;;
			'POSTGAP'*)
				gaps[post,${n}]="$line"
			;;
		esac
	done
}

# Creates a function called 'bin_split', which will run 'bchunk' on the
# input file, capture the output, and make a list of all the files
# created.
bin_split () {
	type="$1"

	case $type in
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

	case $type_tmp in
		'cdr')
			mapfile -t bchunk_cdr_stdout < <(eval "${cdr_args[@]}"; printf '%s\n' "$?")
			elements="${#bchunk_cdr_stdout[@]}"
		;;
		'wav')
			mapfile -t bchunk_wav_stdout < <(eval "${wav_args[@]}"; printf '%s\n' "$?")
			elements="${#bchunk_wav_stdout[@]}"
		;;
	esac

	last=$(( elements - 1 ))

	exit_status_ref="bchunk_${type_tmp}_stdout[-1]"

# Print the output from 'bchunk' if it quits with a non-zero exit
# status.
	if [[ "${!exit_status_ref}" != "0" ]]; then
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

		case $type_tmp in
			'cdr')
				bchunk_cdr_list+=("$line")
			;;
			'wav')
				if [[ $line =~ $regex_iso ]]; then
					bchunk_wav_list+=("$line")

				fi
				if [[ $line =~ $regex_wav ]]; then
					line_tmp=$(sed "s/${regex_wav}/.${type}/" <<<"$line")
					bchunk_wav_list+=("$line_tmp")
				fi
			;;
		esac
	done
}

# Creates a function called 'encode_audio', which will encode the WAVs
# created by 'bchunk'.
encode_audio () {
	type="$1"

	case $type in
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

	rm -f "${of_dn}"/*.wav || exit
}

# Creates a function called 'create_cue', which will create a new CUE
# file, based on the file list created by the 'bin_split' function.
create_cue () {
	type="$1"

	case $type in
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

	case $type_tmp in
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
		if [[ $1 == 'pre' ]]; then
			if [[ ${gaps[pre,${n}]} ]]; then
				eval of_cue_${type}_list+=\(\""    ${gaps[pre,${n}]}"\"\)
			fi
		fi
		if [[ $1 == 'post' ]]; then
			if [[ ${gaps[post,${n}]} ]]; then
				eval of_cue_${type}_list+=\(\""    ${gaps[post,${n}]}"\"\)
			fi
		fi
	}

	for (( i=0; i<elements; i++ )); do
		line_ref="bchunk_${type_tmp}_list[${i}]"

		n=$(( i + 1 ))

		if [[ ${!line_ref} =~ $regex_iso ]]; then
			eval of_cue_${type}_list+=\(\""FILE \\\"${!line_ref%.iso}.bin\\\" BINARY"\"\)
			eval of_cue_${type}_list+=\(\""  ${modes[${n}]}"\"\)
			add_gap pre
			eval of_cue_${type}_list+=\(\""    INDEX 01 00:00:00"\"\)
			add_gap post
		else
			case $type in
				'cdr')
					of_cue_cdr_list+=("FILE \"${!line_ref}\" BINARY")
				;;
				'ogg')
					of_cue_ogg_list+=("FILE \"${!line_ref}\" OGG")
				;;
				'flac')
					of_cue_flac_list+=("FILE \"${!line_ref}\" FLAC")
				;;
			esac

			line_tmp=$(printf "  TRACK %02d AUDIO" "$n")
			
			eval of_cue_${type}_list+=\(\""$line_tmp"\"\)
			add_gap pre
			eval of_cue_${type}_list+=\(\""    INDEX 01 00:00:00"\"\)
			add_gap post
		fi
	done

	# Clearing this array since it's used for both ogg and flac.
	unset -v bchunk_wav_list
}

# Creates a function called 'time_convert', which converts time in the
# 00:00:00 format back and forth between 'frames' / sectors or the time
# format.
time_convert () {
	time="$1"

# If argument is in the 00:00:00 format...
	if [[ $time =~ $regex_time ]]; then
		mapfile -d':' -t time_split <<<"$time"

		time_split[0]=$(sed -E 's/^0{1}//' <<<"${time_split[0]}")
		time_split[1]=$(sed -E 's/^0{1}//' <<<"${time_split[1]}")
		time_split[2]=$(sed -E 's/^0{1}//' <<<"${time_split[2]}")

# Converting minutes and seconds to frames, and adding all the numbers
# together.
		time_split[0]=$(( ${time_split[0]} * 60 * 75 ))
		time_split[1]=$(( ${time_split[1]} * 75 ))

		time=$(( ${time_split[0]} + ${time_split[1]} + ${time_split[2]} ))

# If argument is in the frame format...
	elif [[ $time =~ $regex_frames ]]; then
		s=$(( $time / 75 ))

# While $s (seconds) is equal to (or greater than) 60, clear the $s
# variable and add 1 to the $m (minutes) variable.
		while [[ $s -ge 60 ]]; do
			m=$(( m + 1 ))
			s=$(( s - 60 ))
		done

	# While $m (minutes) is equal to (or greater than) 60, clear the $m
	# variable and add 1 to the $h (hours) variable.
		while [[ $m -ge 60 ]]; do
			h=$(( h + 1 ))
			m=$(( m - 60 ))
		done

	# While $h (hours) is equal to 100 (or greater than), clear the $h
	# variable.
		while [[ $h -ge 100 ]]; do
			h=$(( h - 100 ))
		done

		time=$(printf '%02d:%02d:%02d' "$h" "$m" "$s")
	fi

	printf '%s' "$time"
}

# Creates a function called 'bin_data_track', which copies the raw
# binary data from the original BIN file for the data track.
bin_data_track () {
	for (( i=0; i<${#cue_lines[@]}; i++ )); do
		cue_line="${cue_lines[${i}]}"

		n=$(( i + 1 ))

		if [[ $cue_line =~ $regex_audio ]]; then
			cue_line_next="${cue_lines[${n}]}"

			if [[ $cue_line_next =~ $regex_index ]]; then
				time=$(sed -E "s/${regex_index}/\2/" <<<"$cue_line_next")
				data_frames=$(time_convert "$time")
				break
			fi
		fi
	done

# 2048 bytes is normally the sector size for data CDs / tracks, and 2352
# bytes is the size of audio sectors.
	dd if="$bin" of="$of_bin" bs=2352 count="$data_frames"
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

# Remove the ISO file, since we're gonna copy the raw data track from
# the BIN file instead.
rm -f "$of_iso"

printf '\n'

# Print the created CUE file to the terminal, and to the output file.
for type in "${!audio_types[@]}"; do
	if [[ ${audio_types[${type}]} -eq 0 ]]; then
		continue
	fi

	case $type in
		'cdr')
			elements="${#of_cue_cdr_list[@]}"
		;;
		'ogg')
			elements="${#of_cue_ogg_list[@]}"
		;;
		'flac')
			elements="${#of_cue_flac_list[@]}"
		;;
	esac

	of_cue_ref="of_${type}_cue"

	for (( i=0; i<elements; i++ )); do
		line_ref="of_cue_${type}_list[${i}]"
		printf '%s\r\n' "${!line_ref}"
	done | tee "${!of_cue_ref}"

	printf '\n'
done

printf '\n' 

rm -f "$cue_tmp_f"

# Copy data track from original BIN file.
bin_data_track
