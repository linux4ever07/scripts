#!/bin/bash

# This script looks for CUE/FLAC files (single file FLAC albums) in the
# directories passed to it as arguments. It then proceeds to split the
# FLAC files it finds into separate tracks. Lastly, it copies the tags
# (if available) from the CUE file to the newly split tracks. You need
# 'cuetools' and 'shntool' to run this script.

# The output files are put here:
# ${HOME}/split-tracks/${album}

declare line
declare -a cmd dirs files_in files_out
declare -a format
declare -A if of regex

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

of[dn]="${HOME}/split-tracks"

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
	if[dn]="${dirs[${i}]}"

	mapfile -t files_in < <(find "${if[dn]}" -type f -iname "*.cue")

	files_out+=("${files_in[@]}")
done

unset -v files_in

for (( i = 0; i < ${#files_out[@]}; i++ )); do
	if[cue]="${files_out[${i}]}"
	if[cue_dn]=$(dirname "${if[cue]}")

	declare album fn ext
	declare -a lines files tracks

# Reads the source CUE sheet into RAM.
	mapfile -t lines < <(tr -d '\r' <"${if[cue]}" | sed -E "s/${regex[blank]}/\1/")

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

	fn="${files[0]}"

	unset -v lines files tracks

	album="$fn"

	if [[ $fn =~ ${regex[fn]} ]]; then
		ext="${BASH_REMATCH[2],,}"

		if [[ $ext != 'flac' ]]; then
			unset -v album fn ext

			continue
		fi

		album="${BASH_REMATCH[1]}"
	fi

	of[album_dn]="${of[dn]}/${album}"

	if [[ -d ${of[album_dn]} ]]; then
		unset -v album fn ext

		continue
	fi

	mkdir -p "${of[album_dn]}"
	cd "${of[album_dn]}"

	cuebreakpoints "${if[cue]}" | shnsplit -O always -o flac -- "${if[cue_dn]}/${fn}"
	cuetag.sh "${if[cue]}" split-track*.flac

	unset -v album fn ext
done
