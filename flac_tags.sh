#!/bin/bash

# This script will list tags of a FLAC album. It allows the user to
# select individual tracks from a simple menu, and display the tags.

# Creates a function, called 'usage', which will print usage
# instructions and then quit.
usage () {
	printf '\n%s\n\n' "Usage: $(basename "$0") [dir]"
	exit
}

if [[ ! -d $1 ]]; then
	usage
fi

# If metaflac isn't installed, quit running the script.
command -v metaflac 1>&- || { printf '\n%s\n\n' 'This script requires metaflac.'; exit; }

declare dn
declare -a files

dn=$(readlink -f "$1")

mapfile -t files < <(find "$dn" -maxdepth 1 -type f -iname "*.flac" 2>&- | sort -n)

if [[ ${#files[@]} -eq 0 ]]; then
	usage
fi

declare track
declare -A regex

regex[num]='^[0-9]+$'

# Creates a function, called 'gettags', which gets all the tags present
# in a FLAC file.
gettags () {
	declare if line field
	declare -a lines
	declare -A alltags

	if="$1"

	mapfile -t lines < <(metaflac --no-utf8-convert --export-tags-to=- "$if" 2>&-)

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

	for field in "${!alltags[@]}"; do
		printf '%s\n' "${field}: ${alltags[${field}]}"
	done | sort
}

options () {
	declare ref

	unset -v track

	printf '\n%s\n%s\n\n' '*** BACK (b)' '*** QUIT (q)'

	read -p '>'

	clear

	case "$REPLY" in
		'b')
			return
		;;
		'q')
			exit
		;;
	esac

	if [[ ! $REPLY =~ ${regex[num]} ]]; then
		return
	fi

	ref="files[${REPLY}]"

	if [[ -z ${!ref} ]]; then
		return
	fi

	track="${!ref}"
}

clear

while [[ 1 ]]; do
	printf '\n%s\n\n' '*** CHOOSE TRACK ***'

	for (( i = 0; i < ${#files[@]}; i++ )); do
		printf '%s) %s\n' "$i" "$(basename "${files[${i}]}")"
	done

	options

	if [[ -z $track ]]; then
		continue
	fi

	gettags "$track"

	options
done
