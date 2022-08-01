#!/bin/bash

# This script is simply meant to separate all the tracks (data / audio)
# of BIN/CUE files, and do a byteswap on the audio tracks (to switch the
# endianness). This is needed in some cases to burn games, or the audio
# tracks will be white noise if the endianness is wrong.

# If the -byteswap argument is omitted, then the BIN file is simply
# split into all its separate tracks, but without a byteswap being done
# on the audio tracks.

if=$(readlink -f "$1")

# Creates a function called 'usage', which will print usage and quit.
usage () {
	printf '\n%s\n\n' "Usage: $(basename "$0") [CUE] [-byteswap]"
	exit
}

# If $if is not a real file, print usage and quit.
if [[ ! -f $if ]]; then
	usage
fi

if_bn=$(basename "$if")
if_bn_lc=$(tr '[:upper:]' '[:lower:]' <<<"$if_bn")
if_name="${if_bn_lc%.[^.]*}"
of_name=$(tr '[:blank:]' '_' <<<"$if_name")

if_dn=$(dirname "$if")
of_dn="${PWD}/${of_name}-${RANDOM}"

of_cue="${of_dn}/${of_name}01.cue"
of_bin="${of_dn}/${of_name}01.bin"
of_iso="${of_dn}/${of_name}01.iso"

cue="$if"
cue_tmp_f="/dev/shm/${if_bn%.[^.]*}-${RANDOM}.cue"
bin=$(find "$if_dn" -maxdepth 1 -iname "${if_name}.bin" | head -n 1)

regex_blank='^[[:blank:]]*(.*)[[:blank:]]*$'
regex_fn='^FILE \"{0,1}(.*\/){0,1}(.*)\"{0,1} (.*)$'
regex_bchunk='^ *[0-9]+: (.*\.[[:alpha:]]{3}).*$'
regex_audio='^TRACK [0-9]+ AUDIO$'
regex_audio2='^INDEX 01 ([0-9]{2}:[0-9]{2}:[0-9]{2})$'

declare -a cue_lines bchunk_list of_cue_list
declare data_track_length

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
	mapfile -t cue_lines < <(tr -d '\r' <"$cue")

	declare -a bin_list not_found
	n='0'

	touch "$cue_tmp_f"

	for (( i=0; i<${#cue_lines[@]}; i++ )); do
		cue_lines[${i}]=$(sed -E "s/${regex_blank}/\1/" <<<"${cue_lines[${i}]}")

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
			elif [[ $n -gt 1 ]]; then
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

# If the filenames in the CUE aren't real files, the print the filenames
# and quit.
	for (( i=0; i<${#bin_list[@]}; i++ )); do
		if [[ ! -f ${bin_list[${i}]} ]]; then
			not_found+=("${bin_list[${i}]}")
		fi
	done

	if [[ -n ${not_found[@]} ]]; then
		printf '\n%s\n\n' 'The files below were not found:'

		for (( i=0; i<${#bin_list[@]}; i++ )); do
			printf '%s\n' "${bin_list[${i}]}"
		done

		printf '\n' 

		rm -f "$cue_tmp_f"
		exit
	fi
}

# Creates a function called 'bin_split', which will run 'bchunk' on the
# input file, capture the output, and make a list of all the files
# created.
bin_split () {
	args_tmp=(\""$bin"\" \""$cue_tmp_f"\" \""$of_name"\")

# Creates a function called 'print_stdout', which will be used to print
# the output from 'bchunk' in case it quits with a non-zero exit status.
	print_stdout() {
		for (( i=0; i<${last}; i++ )); do
			printf '%s\n' "${bchunk_stdout[${i}]}"
		done
	}

	if [[ $1 == '-byteswap' ]]; then
		args=(bchunk -s "${args_tmp[@]}")
	else
		args=(bchunk "${args_tmp[@]}")
	fi

	mapfile -t bchunk_stdout < <(eval "${args[@]}"; printf '%s\n' "$?")

	if [[ -n ${bchunk_stdout[@]} ]]; then
		last=$(( ${#bchunk_stdout[@]} - 1 ))
	fi

	if [[ "${bchunk_stdout[${last}]}" != "0" ]]; then
		print_stdout

		exit
	fi

	for (( i=0; i<${#bchunk_stdout[@]}; i++ )); do
		line="${bchunk_stdout[${i}]}"

		if [[ $line == 'Writing tracks:' ]]; then
			n=$(( i + 2 ))
			break
		fi
	done

	for (( i=${n}; i<${#bchunk_stdout[@]}; i++ )); do
		line=$(sed -E "s/${regex_bchunk}/\1/" <<<"${bchunk_stdout[${i}]}")

		if [[ $line =~ .cdr$ ]]; then
			bchunk_list+=("$line")
		fi

		if [[ $line =~ .iso$ ]]; then
			bchunk_list+=("$line")
		fi
	done
}

# Creates a function called 'create_cue', which will create a new CUE
# file, based on the file list created by the 'bin_split' function.
create_cue () {
	n='0'

	regex_mode='^TRACK [0-9]{2,} MODE'

	declare -A gaps
	declare -a modes

# Creates a function called 'add_gap', which will add pregap or postgap,
# if they exist in the source CUE file.
	add_gap () {
		if [[ $1 == 'pre' ]]; then
			if [[ ${gaps[pre,${n}]} ]]; then
				of_cue_list+=("    ${gaps[pre,${n}]}")
			fi
		fi
		if [[ $1 == 'post' ]]; then
			if [[ ${gaps[post,${n}]} ]]; then
				of_cue_list+=("    ${gaps[post,${n}]}")
			fi
		fi
	}

	for (( i=0; i<${#cue_lines[@]}; i++ )); do
		line="${cue_lines[${i}]}"

		case $line in
			'TRACK'*)
				n=$(( n + 1 ))

				if [[ $line =~ $regex_mode ]]; then
					modes[${n}]="$line"
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

	n='0'

	for (( i=0; i<${#bchunk_list[@]}; i++ )); do
		line="${bchunk_list[${i}]}"

		n=$(( n + 1 ))

		if [[ $line =~ .iso$ ]]; then
			line=$(sed 's/.iso$/.bin/' <<<"$line")

			of_cue_list+=("FILE \"${line}\" BINARY")
			of_cue_list+=("  ${modes[${n}]}")
			add_gap pre
			of_cue_list+=("    INDEX 01 00:00:00")
			add_gap post
		fi

		if [[ $line =~ .cdr$ ]]; then
			of_cue_list+=("FILE \"${line}\" BINARY")
			of_cue_list+=( "$(printf "  TRACK %02d AUDIO" "$n")" )
			add_gap pre
			of_cue_list+=("    INDEX 01 00:00:00")
			add_gap post
		fi
	done
}

# Copies the raw BINARY data from the original BIN file for the data
# track.
bin_data_track () {
	for (( i=0; i<${#cue_lines[@]}; i++ )); do
		cue_line=$(sed -E "s/${regex_blank}/\1/" <<<"${cue_lines[${i}]}")

		n=$(( i + 1 ))

		if [[ $cue_line =~ $regex_audio ]]; then
			cue_line_next=$(sed -E "s/${regex_blank}/\1/" <<<"${cue_lines[${n}]}")

			if [[ $cue_line_next =~ $regex_audio2 ]]; then
				mapfile -d':' -t data_track_length < <(sed -E "s/${regex_audio2}/\1/" <<<"$cue_line_next")
				break
			fi
		fi
	done

# Converting minutes and seconds to frames, and adding all the numbers
# together.
	data_track_length[0]=$(( ${data_track_length[0]} * 60 * 75 ))
	data_track_length[1]=$(( ${data_track_length[1]} * 75 ))

	data_frames=$(( ${data_track_length[0]} + ${data_track_length[1]} + ${data_track_length[2]} ))

# 2048 bytes is the sector size normally for data CDs / tracks, and 2352
# is the size of audio sectors.
	dd if="$bin" of="$of_bin" bs=2352 count="$data_frames"
}

# Check if 'oggenc' and 'bchunk' are installed.
check_cmd bchunk

# Create the output directory and change into it.
mkdir "$of_dn" || exit
cd "$of_dn" || exit

# Run the functions.
read_cue
bin_split "$2"
create_cue

# Remove ISO file, since we're gonna copy the BIN data track instead.
rm -f "$of_iso"

# Create output file, or quit.
touch "$of_cue" || exit

printf '\n' 

# Print the created CUE file to the terminal, and to the output file.
for (( i=0; i<${#of_cue_list[@]}; i++ )); do
	printf '%s\r\n' "${of_cue_list[${i}]}" | tee --append "$of_cue"
done

printf '\n' 

rm -f "$cue_tmp_f"

# Copy data track from original BIN file.
bin_data_track
