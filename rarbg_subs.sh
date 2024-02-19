#!/bin/bash

# A simple script to automatically symlink English SRT subtitles (for
# RARBG and VXT releases) to have the same name as the movie file, so
# they will automatically get loaded when the movie plays. The largest
# English SRT file is automatically chosen.

# The script only works with movies, as for right now, and TV series
# are ignored.

# Also:

# magnet:?xt=urn:btih:ulfihylx35oldftn7qosmk6hkhsjq5af

# https://sqlitebrowser.org/

set -eo pipefail

declare -a dirs files vars1
declare -A regex

regex[srt]='\/([0-9]+_)*eng(lish)*.srt$'

vars1=('size' 'dn' 'bn' 'if' 'of')
dirs=("$HOME" "/run/media/${USER}")

get_files () {
	declare srt_tmp size_tmp
	declare -a files_tmp movie_tmp sub_tmp

	for dn in "$@"; do
		mapfile -t files_tmp < <(find "$dn" -type d -name "*-RARBG" -o -name "*-VXT" 2>&-)

		if [[ ${#files_tmp[@]} -eq 0 ]]; then
			continue
		fi

		files+=("${files_tmp[@]}")
	done

	if [[ ${#files[@]} -eq 0 ]]; then
		return
	fi

	printf '\n'

	for (( i = 0; i < ${#files[@]}; i++ )); do
		declare "${vars1[@]}"

		dn="${files[${i}]}"

		mapfile -t movie_tmp < <(compgen -G "${dn}/*.mp4")

		if [[ ${#movie_tmp[@]} -ne 1 ]]; then
			continue
		fi

		mapfile -t sub_tmp < <(compgen -G "${dn}/Subs/*.srt")

		if [[ ${#sub_tmp[@]} -eq 0 ]]; then
			continue
		fi

		size=0

		for (( j = 0; j < ${#sub_tmp[@]}; j++ )); do
			srt_tmp="${sub_tmp[${j}]}"

			if [[ ! ${srt_tmp,,} =~ ${regex[srt]} ]]; then
				continue
			fi

			size_tmp=$(stat -c '%s' "$srt_tmp")

			if [[ $size_tmp -gt $size ]]; then
				size="$size_tmp"

				bn=$(basename "$srt_tmp")
				if="Subs/${bn}"

				of="${movie_tmp[0]%.*}.srt"
			fi
		done

		if [[ -z $of ]]; then
			unset -v "${vars1[@]}"
			continue
		fi

		if [[ -e $of ]]; then
			unset -v "${vars1[@]}"
			continue
		fi

		printf '%s\n' "$if"
		printf '%s\n\n' "$of"

		ln -s "$if" "$of"

		unset -v "${vars1[@]}"
	done
}

get_files "${dirs[@]}"
