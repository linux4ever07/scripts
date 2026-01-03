#!/bin/bash

# This script makes an ASCII tree out of the directory structure in a
# FLAC music library, by reading tags.

# The script expects this directory structure:
# ${input[library_dn]}/${albumartist}/${album}

usage () {
	printf '\n%s\n\n' "Usage: $(basename "$0") [FLAC library directory]"
	exit
}

if [[ ! -d $1 ]]; then
	usage
fi

# If metaflac isn't installed, quit running the script.
command -v metaflac 1>&- || { printf '\n%s\n\n' 'This script requires metaflac.'; exit; }

declare albumartist album date tracks
declare -a dirs1 dirs2 files
declare -A input output alltags

input[library_dn]=$(readlink -f "$1")

gettags () {
	declare line field
	declare -a lines

	for field in "${!alltags[@]}"; do
		unset -v alltags["${field}"]
	done

	mapfile -t lines < <(metaflac --no-utf8-convert --export-tags-to=- "${input[fn]}" 2>&-)

	for (( z = 0; z < ${#lines[@]}; z++ )); do
		line="${lines[${z}]}"

		unset -v mflac
		declare -a mflac

		mflac[0]="${line%%=*}"
		mflac[1]="${line#*=}"

		if [[ -z ${mflac[1]} ]]; then
			continue
		fi

		field="${mflac[0],,}"

		if [[ -n ${alltags[${field}]} ]]; then
			continue
		fi

		alltags["${field}"]="${mflac[1]}"
	done
}

# Enters the Songbird Music Library directory.
cd "${input[library_dn]}"

mapfile -t dirs1 < <(find "${input[library_dn]}" -mindepth 1 -maxdepth 1 -type d 2>&- | sort)

for (( i = 0; i < ${#dirs1[@]}; i++ )); do
	input[artist_dn]="${dirs1[${i}]}"

	if [[ ! -d ${input[artist_dn]} ]]; then
		continue
	fi

	input[fn]=$(find "${input[artist_dn]}" -type f -iname "*.flac" | head -1)

	gettags

	albumartist="${alltags[albumartist]}"

	printf "+---%s\n" "$albumartist"
	printf "|    %s\n" '\'

	mapfile -t dirs2 < <(find "${input[artist_dn]}" -mindepth 1 -maxdepth 1 -type d 2>&- | sort)

	for (( j = 0; j < ${#dirs2[@]}; j++ )); do
		input[album_dn]="${dirs2[${j}]}"

		if [[ ! -d ${input[album_dn]} ]]; then
			continue
		fi

		mapfile -t files < <(find "${input[album_dn]}" -maxdepth 1 -type f -iname "*.flac" 2>&-)

		if [[ ${#files[@]} -eq 0 ]]; then
			continue
		fi

		input[fn]="${files[0]}"

		gettags

		album="${alltags[album]}"
		date="${alltags[date]}"
		tracks="${#files[@]}"

		if [[ -z $date ]]; then
			date="???"
		fi

		printf "|     %s (%s)\n" "$album" "$date"
		printf "|     %s tracks.\n" "$tracks"
		printf "|\n"
	done
done
