#!/bin/bash
# This script is meant to take an input BIN/CUE file, extract the ISO
# (as well as WAV audio tracks) from it, encode the WAV files to high
# bitrate Ogg Vorbis files, and then generate a new CUE file, which
# lists the Ogg Vorbis audio files.
# The purpose of the script is to take DOS games that have CD Audio,
# and getting rid of the need to store the uncompressed CD Audio
# tracks. Ogg Vorbis takes less space and is near the same quality. The
# generated CUE files can be used with DOSBox, by using the 'IMGMOUNT'
# command.
#
# https://www.dosbox.com/wiki/IMGMOUNT

# The '-byteswap' switch is optional. It depends on what byte order
# the input BIN file has. A byteswap may or may not be needed.
# If the byte order is wrong, the Ogg files will be white noise.
# So, it's easy to tell whether or not the byte order is correct.

# You can convert the ISO back to BIN (since it's now stripped of
# its audio tracks). Use PowerISO for Linux, or the Windows version in
# Wine.
#
# https://www.poweriso.com/

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
if_bn_lc=$(sed 's/[[:upper:]]/\L&/g' <<<"$if_bn")
if_name="${if_bn_lc%.cue}"
of_name=$(tr '[:blank:]' '_' <<<"$if_name")

if_dn=$(dirname "$if")
of_dn="${PWD}/${of_name}-${RANDOM}"

of_cue="${of_dn}/${of_name}01.cue"
of_bin="${of_dn}/${of_name}01.bin"

cue="$if"
cue_tmp_f="/dev/shm/${if_bn%.cue}-${RANDOM}.cue"
bin=$(find "$if_dn" -maxdepth 1 -iname "${if_name}.bin" | head -n 1)

declare -a cue_lines bchunk_list of_cue_list

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
		command -v "$cmd" &>/dev/null

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
	mapfile -t cue_lines <"$cue"

	declare -a bin_list not_found
	n='0'

	touch "$cue_tmp_f"

	for (( i=0; i<${#cue_lines[@]}; i++ )); do
		cue_lines[${i}]=$(sed -E 's/^[[:blank:]]*(.*)[[:blank:]]*$/\1/' <<<"${cue_lines[${i}]}")

		if [[ ${cue_lines[${i}]} =~ ^FILE ]]; then

			n=$(( n + 1 ))

# Extracting the filename from line, and removing path from it.
			bin_tmp=$(sed -E 's/^FILE (\"{0,1}.*\"{0,1}) .*$/\1/' <<<"${cue_lines[${i}]}")
			bin_tmp=$(tr -d '"' <<<"$bin_tmp")
			bin_tmp=$(sed 's_.*/__' <<<"$bin_tmp")

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
				printf '\n%s\n' "This CUE file contains multiple FILE commands!"
				printf '%s\n\n' "You need to merge all the containing files into one BIN file, using a tool like PowerISO."
				rm -f "$cue_tmp_f"
				exit
			fi

# Getting the filetype information from line, and replacing line with a
# new one containing the full path to file. We need this, since we're
# creating a temporary input CUE file in /dev/shm, so its location will
# be different from the files it points to.
			f_type=$(sed -E 's/^FILE \"{0,1}.*\"{0,1} (.*)$/\1/' <<<"${cue_lines[${i}]}")
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
		printf '\n%s\n\n' "The files below were not found:"

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
		args=(bchunk -w -s "${args_tmp[@]}")
	else
		args=(bchunk -w "${args_tmp[@]}")
	fi

	mapfile -t bchunk_stdout < <(eval "${args[@]}"; printf '%s\n' "$?")

	if [[ -n ${bchunk_stdout[@]} ]]; then
		last=$(( ${#bchunk_stdout[@]} - 1 ))
	fi

	if [[ ${bchunk_stdout[${last}]} -ne 0 ]]; then
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
		line=$(sed -E 's/^ *[0-9]+: (.*\.[[:alpha:]]{3}).*/\1/' <<<"${bchunk_stdout[${i}]}")

		if [[ $line =~ .wav$ ]]; then
			bchunk_list+=( "$(sed 's/.wav$/.ogg/' <<<"$line")" )
		fi

		if [[ $line =~ .iso$ ]]; then
			bchunk_list+=("$line")
		fi
	done
}

# Creates a function called 'wav2ogg', which will encode the WAVs
# created by 'bchunk'.
wav2ogg () {
	oggenc --quality=10 "${of_dn}"/*.wav || exit

	rm -f "${of_dn}"/*.wav || exit
}

# Creates a function called 'create_cue', which will create a new CUE
# file, based on the file list created by the 'bin_split' function.
create_cue () {
	n='0'

	mode_regex='^TRACK [0-9]{2,} MODE'

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

				if [[ $line =~ $mode_regex ]]; then
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

		if [[ $line =~ .ogg$ ]]; then
			of_cue_list+=("FILE \"${line}\" OGG")
			of_cue_list+=( "$(printf "  TRACK %02d AUDIO" "$n")" )
			add_gap pre
			of_cue_list+=("    INDEX 01 00:00:00")
			add_gap post
		fi
	done
}

# Check if 'oggenc' and 'bchunk' are installed.
check_cmd oggenc bchunk

# Create the output directory and change into it.
mkdir "$of_dn" || exit
cd "$of_dn" || exit

# Run the functions.
read_cue
bin_split "$2"
wav2ogg
create_cue

# Create output file, or quit.
touch "$of_cue" || exit

printf '\n' 

# Print the created CUE file to the terminal, and to the output file.
for (( i=0; i<${#of_cue_list[@]}; i++ )); do
	printf '%s\n' "${of_cue_list[${i}]}" | tee --append "$of_cue"
done

printf '\n' 

rm -f "$cue_tmp_f"
