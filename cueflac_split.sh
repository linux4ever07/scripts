#!/bin/bash

# This script looks for CUE/FLAC files (single FLAC albums) in the
# directories passed to it as arguments. It then proceeds to split the
# FLAC files it finds into separate tracks. Lastly it copies the tags
# (if available) from the CUE file to the newly split tracks. You need
# 'cuetools' and 'shntool' to run this script.

# The output files are put here:
# ${HOME}/split-tracks/${album}

declare of_dn
declare -a cmd dirs files_in files_out
declare -a format
declare -A regex

format[0]='^(FILE) (.*) (.*)$'
format[1]='^(TRACK) ([0-9]{2,}) (.*)$'

regex[blank]='^[[:blank:]]*(.*)[[:blank:]]*$'
regex[path]='^(.*[\\\/])'
regex[fn]='^(.*)\.([^.]*)$'

# Creates an array of the list of commands needed by this script.
cmd=('cuebreakpoints' 'shnsplit')

of_dn="${HOME}/split-tracks"

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
# necessary commands are installed. If any of the commands are missing
# print them and quit.
check_cmd () {
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

for (( i = 0; i < ${#dirs[@]}; i++ )); do
	dn="${dirs[${i}]}"

	mapfile -t files_in < <(find "$dn" -type f -iname "*.cue")

	files_out+=("${files_in[@]}")
done

unset -v files_in

for (( i = 0; i < ${#files_out[@]}; i++ )); do
	cue="${files_out[${i}]}"
	cue_dn=$(dirname "$cue")

	declare album fn ext
	declare -a lines files tracks

# Reads the source CUE sheet into RAM.
	mapfile -t lines < <(tr -d '\r' <"$cue" | sed -E "s/${regex[blank]}/\1/")

# This loop processes each line in the CUE sheet, and stores all the
# containing file names in the 'files' array.
	for (( j = 0; j < ${#lines[@]}; j++ )); do
		line="${lines[${j}]}"

		if [[ $line =~ ${format[0]} ]]; then
			files+=("$(tr -d '"' <<<"${BASH_REMATCH[2]}" | sed -E "s/${regex[path]}//")")
		fi

		if [[ $line =~ ${format[1]} ]]; then
			tracks+=("${BASH_REMATCH[2]}")
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

	split_dn="${of_dn}/${album}"

	if [[ -d $split_dn ]]; then
		unset -v album fn ext

		continue
	fi

	mkdir -p "$split_dn"
	cd "$split_dn"

	cuebreakpoints "$cue" | shnsplit -O always -o flac -- "${cue_dn}/${fn}"
	cuetag.sh "$cue" split-track*.flac

	unset -v album fn ext
done
