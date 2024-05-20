#!/bin/bash

# This script looks for FLAC files in the current directory and creates
# a tracklist from the tags.

# If metaflac isn't installed, quit running the script.
command -v metaflac 1>&- || { printf '\n%s\n\n' 'This script requires metaflac.'; exit; }

declare if albumartist artist album date tracks track title
declare length total_length time total_time
declare -a files
declare -A alltags

# Creates a function, called 'gettags', which gets all the tags present
# in a FLAC file.
gettags () {
	declare line field
	declare -a lines

	for field in "${!alltags[@]}"; do
		unset -v alltags["${field}"]
	done

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
}

# Find FLAC files in the current directory.
mapfile -t files < <(find "$PWD" -maxdepth 1 -type f -iname "*.flac" 2>&- | sort -n)

# If there are no FLAC files in the dir, quit.
if [[ ${#files[@]} -eq 0 ]]; then
	printf '\n%s\n\n' 'There are no FLAC files in this directory.'
	exit
fi

if="${files[0]}"

gettags

albumartist="${alltags[albumartist]}"
album="${alltags[album]}"
date="${alltags[date]}"
tracks="${#files[@]}"

# Function to calculate seconds for a track.
# Usage: time_seconds <file>
time_seconds () {
	declare samples rate

	samples=$(metaflac --show-total-samples "$1")
	rate=$(metaflac --show-sample-rate "$1")
	printf '%d' "$(( samples / rate ))"
}

# Function to make the time a little more readable.
# Usage: time_readable <integer value>
# Since the positional parameter is an integer we have to put a $ in
# front of it so it doesn't get interpreted as a regular integer.
time_readable () {
	declare minutes seconds

	minutes=$(( $1 / 60 ))
	seconds=$(( $1 % 60 ))
	printf '%d:%02d' "$minutes" "$seconds"
}

# Calculates the time of all tracks combined in seconds and stores the
# value in the $total_length variable.
for (( i = 0; i < ${#files[@]}; i++ )); do
	(( total_length += $(time_seconds "${files[${i}]}") ))
done

# Makes the time readable.
total_time=$(time_readable "$total_length")

# Prints album information.
cat <<INFO

Artist: ${albumartist}
Album: ${album}
Date: ${date}
Tracks: ${tracks}
Total time: ${total_time}

Tracklist

INFO

# Prints the track names and their duration.
for (( i = 0; i < ${#files[@]}; i++ )); do
	if="${files[${i}]}"

	gettags

	artist="${alltags[artist]}"
	track="${alltags[tracknumber]}"
	title="${alltags[title]}"

	length=$(time_seconds "$if")
	time=$(time_readable "$length")

	printf '%02d. %s - %s (%s)\n' "$track" "$artist" "$title" "$time"
done

printf '\n'
