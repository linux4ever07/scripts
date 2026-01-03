#!/bin/bash

# This script looks for CUE/FLAC files (single file FLAC albums) in the
# directories passed to it as arguments. It then proceeds to split the
# FLAC files it finds into separate tracks. Lastly, it copies the tags
# (if available) from the CUE file to the newly split tracks. You need
# 'cuetools' and 'shntool' to run this script.

# The output files are put here:
# ${HOME}/split-tracks/${no_ext}

declare line
declare -a format cmd dirs files_in files_out
declare -A input output regex

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

# Creates an array of the list of commands needed by this script.
cmd=('cuebreakpoints' 'shnsplit')

output[dn]="${HOME}/split-tracks"

# Creates a function, called 'usage', which will print usage
# instructions and then quit.
usage () {
	printf '\n%s\n\n' "Usage: $(basename "$0") [dirs]"
	exit
}

if [[ $# -eq 0 ]]; then
	usage
fi

while [[ $# -gt 0 ]]; do
	if [[ -d $1 ]]; then
		dirs+=("$(readlink -f "$1")")
	else
		usage
	fi

	shift
done

if [[ ${#dirs[@]} -eq 0 ]]; then
	usage
fi

# Creates a function, called 'check_cmd', which will check if the
# necessary commands are installed. If any of the commands are missing,
# print them and quit.
check_cmd () {
	declare cmd_tmp
	declare -a missing_pkg
	declare -A cmd_pkg

# Saves the package names of the commands that are needed by the script.
	cmd_pkg["${cmd[0]}"]='cuetools'
	cmd_pkg["${cmd[1]}"]='shntool'

	for cmd_tmp in "${cmd[@]}"; do
		command -v "$cmd_tmp" 1>&-

		if [[ $? -ne 0 ]]; then
			missing_pkg+=("$cmd_tmp")
		fi
	done

	if [[ ${#missing_pkg[@]} -gt 0 ]]; then
		printf '\n%s\n\n' 'You need to install the following through your package manager:'

		for cmd_tmp in "${missing_pkg[@]}"; do
			printf '%s\n' "${cmd_pkg[${cmd_tmp}]}"
		done

		printf '\n'

		exit
	fi
}

check_cmd "${cmd[@]}"

for (( i = 0; i < ${#dirs[@]}; i++ )); do
	input[dn]="${dirs[${i}]}"

	mapfile -t files_in < <(find "${input[dn]}" -type f -iname "*.cue")

	files_out+=("${files_in[@]}")
done

unset -v files_in

for (( i = 0; i < ${#files_out[@]}; i++ )); do
	input[cue_fn]="${files_out[${i}]}"
	input[cue_dn]=$(dirname "${input[cue_fn]}")

	declare no_ext ext
	declare -a lines files tracks

# Reads the source CUE sheet into RAM.
	mapfile -t lines < <(tr -d '\r' <"${input[cue_fn]}" | sed -E "s/${regex[blank]}/\1/")

# This loop processes each line in the CUE sheet, and stores all the
# containing file names in the 'files' array.
	for (( j = 0; j < ${#lines[@]}; j++ )); do
		line="${lines[${j}]}"

		if [[ $line =~ ${format[3]} ]]; then
			line="${BASH_REMATCH[2]}"

			if [[ $line =~ ${regex[quotes]} ]]; then
				line="${BASH_REMATCH[1]}"
			fi

			if [[ $line =~ ${regex[path]} ]]; then
				line="${BASH_REMATCH[2]}"
			fi

			files+=("$line")

			continue
		fi

		if [[ $line =~ ${format[4]} ]]; then
			line="${BASH_REMATCH[2]}"

			tracks+=("$line")

			continue
		fi
	done

	if [[ ${#files[@]} -gt 1 || ${#tracks[@]} -eq 1 ]]; then
		unset -v lines files tracks

		continue
	fi

	input[fn]="${files[0]}"

	unset -v lines files tracks

	if [[ ${input[fn]} =~ ${regex[fn]} ]]; then
		no_ext="${BASH_REMATCH[1]}"
		ext="${BASH_REMATCH[2],,}"

		if [[ $ext != 'flac' ]]; then
			unset -v no_ext ext

			continue
		fi
	fi

	output[album_dn]="${output[dn]}/${no_ext}"

	if [[ -d ${output[album_dn]} ]]; then
		unset -v no_ext ext

		continue
	fi

	mkdir -p "${output[album_dn]}"
	cd "${output[album_dn]}"

	cuebreakpoints "${input[cue_fn]}" | shnsplit -O always -o flac -- "${input[cue_dn]}/${input[fn]}"
	cuetag.sh "${input[cue_fn]}" split-track*.flac

	unset -v no_ext ext
done
