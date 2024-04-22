#!/bin/bash

# This script is meant to separate the tracks of BeOS disc images
# (CUE/BIN), rename the tracks, and backup the 1st track (the boot
# floppy image) to a created sub-directory.

# The BeOS disc image directory is recursively lowercased, before doing
# anything else. This is to make sure there will be no name conflicts.

# This script depends on:
# * ch_case.sh
# * cuebin_extract.sh

set -eo pipefail

# Creates a function, called 'usage', which will print usage
# instructions and then quit.
usage () {
	printf '\n%s\n\n' "Usage: $(basename "$0") [dir]"
	exit
}

if [[ ! -d $1 ]]; then
	usage
fi

declare session line name md5 size size_limit
declare -a cue_files bin_files cue_dirs lines format match
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
regex[dn]='^(.*)-[0-9]+-[0-9]+$'
regex[cuebin]='^(.*)[0-9]{2}_cdr.cue$'

session="${RANDOM}-${RANDOM}"

size_limit=3145728

if[dn]=$(readlink -f "$1")
of[dn_cuebin]="${if[dn]}/cuebin"
of[dn_floppy]="${if[dn]}/floppy"

# Creates a function, called 'get_files', which will be used to generate
# file lists to be used by other functions.
get_files () {
	declare glob

	for glob in "$@"; do
		compgen -G "$glob"
	done | sort -n
}

ch_case.sh "${if[dn]}" lower

mapfile -t cue_files < <(find "${if[dn]}" -type f -iname "*.cue")

mkdir -p "${of[dn_cuebin]}" "${of[dn_floppy]}" || exit
cd "${of[dn_cuebin]}" || exit

for (( i = 0; i < ${#cue_files[@]}; i++ )); do
	if[fn]="${cue_files[${i}]}"
	if[dn]=$(dirname "${if[fn]}")
	if[bn]=$(basename "${if[fn]}")

	of[bn]=$(sed -E 's/ +/_/g' <<<"${if[bn],,}")

	if[cue]="${if[fn]}"
	of[cue]="${if[dn]}/${of[bn]}"

	if [[ ${if[cue]} != "${of[cue]}" ]]; then
		mv "${if[cue]}" "${of[cue]}" || exit
	fi

	printf '%s\n\n' "*** ${of[cue]}"

	mapfile -t lines < <(tr -d '\r' <"${of[cue]}" | sed -E "s/${regex[blank]}/\1/")

	truncate -s 0 "${of[cue]}"

	for (( j = 0; j < ${#lines[@]}; j++ )); do
		line="${lines[${j}]}"

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

			match[1]="\"${match[1],,}\""

			line="${match[@]}"
		fi

		printf '%s\r\n' "$line" >> "${of[cue]}"
	done

	cuebin_extract.sh "${of[cue]}" -cdr
done

mapfile -t cue_dirs < <(find "${of[dn_cuebin]}" -mindepth 1 -maxdepth 1 -type d)

for (( i = 0; i < ${#cue_dirs[@]}; i++ )); do
	if[dn]="${cue_dirs[${i}]}"

	cd "${if[dn]}" || exit

	mapfile -t cue_files < <(get_files "*.cue")
	mapfile -t bin_files < <(get_files "*.bin" "*.cdr")

	if [[ ${#cue_files[@]} -eq 0 ]]; then
		continue
	fi

	if [[ ${#bin_files[@]} -lt 2 ]]; then
		continue
	fi

	if [[ ! ${cue_files[0]} =~ ${regex[cuebin]} ]]; then
		continue
	fi

	name="${BASH_REMATCH[1]}"

	mv "${cue_files[0]}" "${name}.cue" || exit
	cue_files[0]="${name}.cue"

	size=$(stat -c '%s' "${bin_files[0]}")

	if [[ $size -gt $size_limit ]]; then
		continue
	fi

	md5=$(md5sum -b "${bin_files[0]}")
	md5="${md5%% *}"

	of[floppy]="floppy_${md5}.bin"

	mapfile -t lines < <(tr -d '\r' <"${cue_files[0]}" | sed -E "s/${bin_files[0]}/${of[floppy]}/")
	printf '%s\r\n' "${lines[@]}" > "${cue_files[0]}"

	mv -n "${bin_files[0]}" "${of[floppy]}" || exit
	cp -p "${of[floppy]}" "${of[dn_floppy]}" || exit
done

cd "${of[dn_cuebin]}" || exit

for (( i = 0; i < ${#cue_dirs[@]}; i++ )); do
	if[dn]="${cue_dirs[${i}]}"
	if[bn]=$(basename "${if[dn]}")

	if [[ ${if[bn]} =~ ${regex[dn]} ]]; then
		of[dn]="${BASH_REMATCH[1]}"
	fi

	if [[ -d ${of[dn]} ]]; then
		continue
	fi

	mv -n "${if[bn]}" "${of[dn]}" || exit
done
