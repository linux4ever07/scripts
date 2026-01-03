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
regex[dn]='^(.*)-[0-9]+-[0-9]+$'
regex[cuebin]='^(.*)[0-9]{2}_cdr.cue$'

session="${RANDOM}-${RANDOM}"

size_limit=3145728

input[dn]=$(readlink -f "$1")
output[cuebin_dn]="${input[dn]}/cuebin"
output[floppy_dn]="${input[dn]}/floppy"

# Creates a function, called 'get_files', which will be used to generate
# file lists to be used by other functions.
get_files () {
	declare glob

	for glob in "$@"; do
		compgen -G "$glob"
	done | sort -n
}

ch_case.sh "${input[dn]}" lower

mapfile -t cue_files < <(find "${input[dn]}" -type f -iname "*.cue")

mkdir -p "${output[cuebin_dn]}" "${output[floppy_dn]}"
cd "${output[cuebin_dn]}"

for (( i = 0; i < ${#cue_files[@]}; i++ )); do
	input[fn]="${cue_files[${i}]}"
	input[dn]=$(dirname "${input[fn]}")
	input[bn]=$(basename "${input[fn]}")

	output[bn]=$(sed -E 's/ +/_/g' <<<"${input[bn],,}")

	input[cue_fn]="${input[fn]}"
	output[cue_fn]="${input[dn]}/${output[bn]}"

	if [[ ${input[cue_fn]} != "${output[cue_fn]}" ]]; then
		mv "${input[cue_fn]}" "${output[cue_fn]}"
	fi

	printf '%s\n\n' "*** ${output[cue_fn]}"

	mapfile -t lines < <(tr -d '\r' <"${output[cue_fn]}" | sed -E "s/${regex[blank]}/\1/")

	truncate -s 0 "${output[cue_fn]}"

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

		printf '%s\r\n' "$line" >> "${output[cue_fn]}"
	done

	cuebin_extract.sh "${output[cue_fn]}" -cdr
done

mapfile -t cue_dirs < <(find "${output[cuebin_dn]}" -mindepth 1 -maxdepth 1 -type d)

for (( i = 0; i < ${#cue_dirs[@]}; i++ )); do
	input[dn]="${cue_dirs[${i}]}"

	cd "${input[dn]}"

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

	mv "${cue_files[0]}" "${name}.cue"
	cue_files[0]="${name}.cue"

	size=$(stat -c '%s' "${bin_files[0]}")

	if [[ $size -gt $size_limit ]]; then
		continue
	fi

	md5=$(md5sum -b "${bin_files[0]}")
	md5="${md5%% *}"

	output[floppy]="floppy_${md5}.bin"

	mapfile -t lines < <(tr -d '\r' <"${cue_files[0]}" | sed -E "s/${bin_files[0]}/${output[floppy]}/")
	printf '%s\r\n' "${lines[@]}" > "${cue_files[0]}"

	mv -n "${bin_files[0]}" "${output[floppy]}"
	cp -p "${output[floppy]}" "${output[floppy_dn]}"
done

cd "${output[cuebin_dn]}"

for (( i = 0; i < ${#cue_dirs[@]}; i++ )); do
	input[tmp_dn]="${cue_dirs[${i}]}"
	input[tmp_bn]=$(basename "${input[tmp_dn]}")

	if [[ ${input[tmp_bn]} =~ ${regex[dn]} ]]; then
		output[dn]="${BASH_REMATCH[1]}"
	fi

	if [[ -d ${output[dn]} ]]; then
		continue
	fi

	mv -n "${input[tmp_bn]}" "${output[dn]}"
done
