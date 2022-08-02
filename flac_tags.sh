#!/bin/bash
# This script will list tags of a FLAC album. It allows the user to
# select individual tracks from a simple menu, and display the tags.

usage () {
	printf '%s\n\n' "Usage: $(basename "$0") [dir]"
	exit
}

if [[ ! -d $1 ]]; then
	usage
fi

dn=$(readlink -f "$1")

mapfile -t files < <(find "$dn" -maxdepth 1 -type f -iname "*.flac" 2>&- | sort -n)

if [[ -z ${files[@]} ]]; then
	usage
fi

declare track

gettags () {
	if="$1"

	declare -A alltags

	mapfile -t lines < <(metaflac --no-utf8-convert --export-tags-to=- "$if")

	for (( j=0; j<${#lines[@]}; j++ )); do
		line="${lines[${j}]}"

		unset -v mflac

		mflac[0]=$(cut -d'=' -f1 <<<"$line")
		mflac[1]=$(cut -d'=' -f2- <<<"$line")

		if [[ -z ${mflac[1]} ]]; then
			continue
		fi

		field=$(tr '[:upper:]' '[:lower:]' <<<"${mflac[0]}")

		if [[ -n ${alltags[${field}]} ]]; then
			continue
		fi

		alltags[${field}]="${mflac[1]}"
	done

	for field in "${!alltags[@]}"; do
		printf '%s\n' "${field}: ${alltags[${field}]}"
	done | sort
}

options () {
	type="$1"

	regex='^[[:digit:]]+$'

	limit=$(( ${#files[@]} - 1 ))

	read track

	case "$track" in
		'b')
			unset -v track
			return
		;;
		'q')
			exit
		;;
	esac

	if [[ $type == 'flac_out' ]]; then
		unset -v track
		return
	fi

	if [[ ! $track =~ $regex || $track -gt $limit ]]; then
		unset -v track
		return
	fi
}

check_options () {
	type="$1"

	printf '\n%s\n%s\n' '*** BACK (b)' '*** QUIT (q)'
	printf '\n%s' '>'

	options "$type"

	clear
}

clear

while true; do
	printf '\n%s\n\n' '*** CHOOSE TRACK ***'

	for (( i = 0; i < ${#files[@]}; i++ )); do
		printf '%s) %s\n' "$i" "$(basename "${files[${i}]}")"
	done

	check_options 'files'

	if [[ -z $track ]]; then
		continue
	fi

	mapfile -t flac_out < <(gettags "${files[${track}]}")

	for (( i = 0; i < ${#flac_out[@]}; i++ )); do
		printf '%s\n' "${flac_out[${i}]}"
	done

	check_options 'flac_out'
done