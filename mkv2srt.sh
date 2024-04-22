#!/bin/bash

# This script is meant to extract SubRip (SRT) subtitles from MKV
# (Matroska) files, and remux them without the SRT tracks.

# I use this script in combination with 'extract_subs.sh', to backup
# the subtitles when I replace old movie rips (like XviD, H264 etc.)
# with better rips (HEVC / x265).

# If there's still other track types (subtitle or not) besides SRT left
# in the Matroska file after extraction, then it's remuxed. If there's
# no other tracks left at all, it's deleted.

# It's a good idea to keep SRT subtitles as regular text files, because
# then the checksum can be compared against other files. Hence,
# duplicates can be found and deleted. It also means the SRT subtitles
# are more accessible in general, if they need to be edited, synced to
# a different movie release etc.

declare tracks_n
declare -a cmd files_tmp
declare -A if of regex tracks

regex[start]='^\|\+ Tracks$'
regex[stop]='^\|\+ '
regex[strip]='^\| +\+ (.*)$'
regex[track]='^Track$'
regex[num]='^Track number: [0-9]+ \(track ID for mkvmerge & mkvextract: ([0-9]+)\)$'
regex[sub]='^Track type: subtitles$'
regex[codec]='^Codec ID: (.*)$'
regex[srt]='^S_TEXT\/UTF8$'
regex[lang]='^Language( \(.*\)){0,1}: (.*)$'
regex[name]='^Name: (.*)$'

regex[fn]='^(.*)\.([^.]*)$'
regex[lang_arg]='^[[:alpha:]]{3}$'

tracks_n=0

mapfile -t cmd < <(command -v mkvinfo mkvmerge)

if [[ ${#cmd[@]} -ne 2 ]]; then
	printf '\nThis script needs %s installed!\n\n' 'mkvtoolnix'
	exit
fi

# Creates a function, called 'usage', which will print usage
# instructions and then quit.
usage () {
	printf '\n%s\n\n' "Usage: $(basename "$0") [mkv]"
	exit
}

# Creates a function, called 'clean_up', which will remove temporary
# files, if they exist.
clean_up () {
	if [[ ${#files_tmp[@]} -eq 0 ]]; then
		return
	fi

	for (( i = 0; i < ${#files_tmp[@]}; i++ )); do
		if[fn_tmp]="${files_tmp[${i}]}"

		if [[ -f ${if[fn_tmp]} ]]; then
			rm "${if[fn_tmp]}"
		fi
	done
}

# Creates a function, called 'set_names', which will create variables
# for file names.
set_names () {
	if[fn]=$(readlink -f "$1")
	if[dn]=$(dirname "${if[fn]}")
	if[bn]=$(basename "${if[fn]}")

	if[bn_lc]="${if[bn],,}"

	of[dn]="${if[dn]}/${if[bn]%.*}"
	of[mkv]="${of[dn]}/${if[bn]}"

	if [[ ${if[bn_lc]##*.} != 'mkv' ]]; then
		usage
	fi
}

# Creates a function, called 'get_tracks', which will read the metadata
# of media files, and if they contain subtitle tracks, store those in
# the 'sub_tracks' hash.
get_tracks () {
	declare switch line
	declare -a mkvinfo_lines mkvinfo_tracks

	mapfile -t mkvinfo_lines < <(mkvinfo "${if[fn]}" 2>&-)

# Singles out the part that lists the tracks, and ignores the rest of
# the output from 'mkvinfo'.
	switch=0

	for (( i = 0; i < ${#mkvinfo_lines[@]}; i++ )); do
		line="${mkvinfo_lines[${i}]}"

		if [[ $line =~ ${regex[start]} ]]; then
			switch=1
			continue
		fi

		if [[ $switch -eq 0 ]]; then
			continue
		fi

		if [[ $line =~ ${regex[stop]} ]]; then
			switch=0
			break
		fi

		if [[ $line =~ ${regex[strip]} ]]; then
			line="${BASH_REMATCH[1]}"
		fi

		mkvinfo_tracks+=("$line")
	done

	unset -v mkvinfo_lines

	for (( i = 0; i < ${#mkvinfo_tracks[@]}; i++ )); do
		line="${mkvinfo_tracks[${i}]}"

		if [[ $line =~ ${regex[track]} ]]; then
			(( tracks_n += 1 ))
			tracks["${tracks_n},sub"]=0
			tracks["${tracks_n},srt"]=0
		fi

		if [[ $line =~ ${regex[num]} ]]; then
			tracks["${tracks_n},num"]="${BASH_REMATCH[1]}"
		fi

		if [[ $line =~ ${regex[sub]} ]]; then
			tracks["${tracks_n},sub"]=1
		fi

		if [[ $line =~ ${regex[codec]} ]]; then
			if [[ ${BASH_REMATCH[1]} =~ ${regex[srt]} ]]; then
				tracks["${tracks_n},srt"]=1
			fi
		fi

# For some tracks, the language can be listed twice. First with a
# three-letter code, and then with a two-letter code. The first code is
# preferred by this script.
		if [[ $line =~ ${regex[lang]} ]]; then
			if [[ -z ${tracks[${tracks_n},lang]} ]]; then
				tracks["${tracks_n},lang"]="${BASH_REMATCH[2],,}"
			fi
		fi

		if [[ $line =~ ${regex[name]} ]]; then
			if [[ -z ${tracks[${tracks_n},name]} ]]; then
				tracks["${tracks_n},name"]="${BASH_REMATCH[1]}"
			fi
		fi
	done

	(( tracks_n += 1 ))

	unset -v mkvinfo_tracks
}

# Creates a function, called 'extract_remux', which will extract SRT
# subtitles from the Matroska file, and remux it without the SRT
# subtitles.
extract_remux () {
	declare switch string
	declare num_tmp sub_tmp srt_tmp lang_tmp name_tmp
	declare -a args_srt args_not args_string full_args

	switch=0

# If no subtitles have been found, quit.
	if [[ ${#tracks[@]} -eq 0 ]]; then
		usage
	fi

# Puts together the mkvmerge command. The loop below deals with
# subtitles that are in the Matroska file.
	for (( i = 1; i < tracks_n; i++ )); do
		num_tmp="${tracks[${i},num]}"
		sub_tmp="${tracks[${i},sub]}"
		srt_tmp="${tracks[${i},srt]}"
		lang_tmp="${tracks[${i},lang]}"
		name_tmp="${tracks[${i},name]}"

		if [[ -z $lang_tmp ]]; then
			lang_tmp='und'
		fi

		if [[ -z $name_tmp ]]; then
			name_tmp='und'
		fi

		if [[ $sub_tmp -eq 0 ]]; then
			switch=1
			continue
		fi

		if [[ $srt_tmp -eq 1 ]]; then
			of[srt]="${of[dn]}/${num_tmp}_${lang_tmp}_${name_tmp}.srt"
			files_tmp+=("${of[srt]}")

			args_srt+=(\""${num_tmp}:${of[srt]}"\")
		fi

		if [[ $srt_tmp -eq 0 ]]; then
			switch=1
			args_not+=("$num_tmp")
		fi
	done

# If there's no SRT subtitles in the Matroska file, quit.
	if [[ ${#args_srt[@]} -eq 0 ]]; then
		printf '\n%s\n\n' "There are no SRT subtitles in: ${if[bn]}"
		exit
	fi

	if [[ -d ${of[dn]} ]]; then
		return
	fi

	mkdir -p "${of[dn]}"

	full_args=(mkvextract \""${if[fn]}"\" tracks "${args_srt[@]}")

# Runs mkvextract, and prints the command.
	eval "${full_args[@]}"

	if [[ $? -ne 0 ]]; then
		clean_up
		exit
	fi

	printf '\n'

# Change line-endings to make the files compatible with DOS/Windows.
	unix2dos "${files_tmp[@]}"

	files_tmp+=("${of[mkv]}")

	string="${full_args[@]}"
	printf '\n%s\n\n' "$string"

	args_string=$(printf '%s,' "${args_not[@]}")
	args_string="${args_string%,}"

	full_args=(mkvmerge -o \""${of[mkv]}"\" '--subtitle-tracks' \""${args_string}"\" \""${if[fn]}"\")

# Runs mkvmerge, and prints the command.
	if [[ $switch -eq 1 ]]; then
		eval "${full_args[@]}"

		if [[ $? -ne 0 ]]; then
			clean_up
			exit
		fi

		string="${full_args[@]}"
		printf '\n%s\n\n' "$string"
	fi

# Removes original MKV file.
	rm "${if[fn]}"

# Resets the tracks and files variables.
	tracks=()
	files_tmp=()
	tracks_n=0
}

# The loop below handles the arguments to the script.
while [[ $# -gt 0 ]]; do
	if [[ -f $1 ]]; then
		set_names "$1"
		get_tracks
		extract_remux

		shift
	else
		usage
	fi
done
