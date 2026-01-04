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

declare key
declare -a dirs files
declare -A input output regex

regex[srt]='\/([[:digit:]]+_)*eng(lish)*.srt$'

dirs=("$HOME" "/run/media/${USER}")

get_files () {
	declare srt_tmp size_tmp size
	declare -a files_tmp movie_tmp sub_tmp

	for key in "$@"; do
		input[dn]="$key"

		mapfile -t files_tmp < <(find "${input[dn]}" -type d -name "*-RARBG" -o -name "*-VXT" 2>&-)

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
		size=0

		input=()
		output=()

		input[dn]="${files[${i}]}"

		mapfile -t movie_tmp < <(compgen -G "${input[dn]}/*.mp4")

		if [[ ${#movie_tmp[@]} -ne 1 ]]; then
			continue
		fi

		mapfile -t sub_tmp < <(compgen -G "${input[dn]}/Subs/*.srt")

		if [[ ${#sub_tmp[@]} -eq 0 ]]; then
			continue
		fi

		for (( j = 0; j < ${#sub_tmp[@]}; j++ )); do
			srt_tmp="${sub_tmp[${j}]}"

			if [[ ! ${srt_tmp,,} =~ ${regex[srt]} ]]; then
				continue
			fi

			size_tmp=$(stat -c '%s' "$srt_tmp")

			if [[ $size_tmp -gt $size ]]; then
				size="$size_tmp"

				input[bn]=$(basename "$srt_tmp")
				input[fn]="Subs/${input[bn]}"

				output[fn]="${movie_tmp[0]%.*}.srt"
			fi
		done

		if [[ -z ${output[fn]} ]]; then
			continue
		fi

		if [[ -e ${output[fn]} ]]; then
			continue
		fi

		printf '%s\n' "${input[fn]}"
		printf '%s\n\n' "${output[fn]}"

		ln -s "${input[fn]}" "${output[fn]}"
	done
}

get_files "${dirs[@]}"
