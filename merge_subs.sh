#!/bin/bash

# This script is meant to mux extra subtitles into an MKV (Matroska)
# file, and also set the default subtitle. It asks the user to select
# the default subtitle from a menu.

# Even if the video file given as first argument is not an MKV, it will
# still probably be able to be processed, as long as 'mkvmerge' supports
# it. The output file will be MKV no matter what.

# All video / subtitle files passed to the script that are not Matroska
# will be temporarily converted to Matroska so their metadata can be
# read by 'mkvinfo'. The temporary files are deleted after the script is
# done.

if=$(readlink -f "$1")

session="${RANDOM}-${RANDOM}"
of="${if%.[^.]*}-${session}.mkv"

sub_tracks_n=0
declare -a files tmp_files args1 args2 full_args
declare -A sub_tracks

regex_start='^\|\+ Tracks$'
regex_stop='^\|\+ '
regex_line='^\| +\+ '
regex_track="${regex_line}Track$"
regex_num="${regex_line}Track number: [0-9]+ \(track ID for mkvmerge & mkvextract: ([0-9]+)\)$"
regex_sub="${regex_line}Track type: subtitles$"
regex_lang="${regex_line}Language( \(.*\)){0,1}: (.*)$"
regex_name="${regex_line}Name: (.*)$"

regex_fn='^(.*)\.([^.]*)$'
regex_lang_arg='^[[:alpha:]]{3}$'

# Creates a function called 'usage', which will print usage instructions
# and then quit.
usage () {
	cat <<USAGE

Usage: $(basename "$0") [mkv] [srt] [args] [...]

	Optional arguments:

[srt]
	File name of subtitle to be added (needs to be specified before the
	other arguments).

-lang [code]
	Three-letter language code for added subtitle.

-name [...]
	Name for added subtitle.

USAGE
	exit
}

command -v mkvinfo 1>&- 2>&-

if [[ $? -ne 0 ]]; then
	printf '\nThis script needs %s installed!\n\n' 'mkvtoolnix'
	exit
fi

# Creates a function called 'get_tracks', which will read the metadata
# of media files, and if they contain subtitle tracks, store those in
# the 'sub_tracks' hash.
get_tracks () {
	if_tmp=$(readlink -f "$1")
	bn_tmp=$(basename "$if_tmp")
	dn_tmp=$(dirname "$if_tmp")

	declare ext_tmp of_tmp
	declare -a mkvinfo_tracks
	declare -A tracks

# Parses the input file name, and separates basename from extension.
# If this fails, return from the function.
	if [[ ${bn_tmp,,} =~ $regex_fn ]]; then
		match=("${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}")
		ext_tmp="${match[1]}"
		session_tmp="${RANDOM}-${RANDOM}"
		of_tmp="${dn_tmp}/${match[0]}-tmp-${session_tmp}.mkv"
	else
		return
	fi

# If input file is not a Matroska file, remux it to a temporary MKV,
# add the file name to the 'tmp_files' array, so it can be deleted
# later.
	if [[ $ext_tmp != 'mkv' ]]; then
		mapfile -t mkvmerge_lines < <(mkvmerge -o "$of_tmp" "$if_tmp" 2>&-)

		if [[ $? -ne 0 ]]; then
			return
		fi

		tmp_files+=("$of_tmp")
		if_tmp="$of_tmp"
	fi

	files+=("$if_tmp")

	mapfile -t mkvinfo_lines < <(mkvinfo "$if_tmp" 2>&-)

# Singles out the part that lists the tracks, and ignores the rest of
# the output from 'mkvinfo'.
	switch=0

	for (( i = 0; i < ${#mkvinfo_lines[@]}; i++ )); do
		line="${mkvinfo_lines[${i}]}"

		if [[ $line =~ $regex_start ]]; then
			switch=1
			continue
		fi

		if [[ $switch -eq 1 ]]; then
			if [[ $line =~ $regex_stop ]]; then
				switch=0
				break
			fi

			mkvinfo_tracks+=("$line")
		fi
	done

# Gets all tracks from Matroska file.
	tracks_n=0

	for (( i = 0; i < ${#mkvinfo_tracks[@]}; i++ )); do
		line="${mkvinfo_tracks[${i}]}"

		if [[ $line =~ $regex_track ]]; then
			tracks_n=$(( tracks_n + 1 ))

			tracks[${tracks_n},sub]=0
		fi

		if [[ $line =~ $regex_num ]]; then
			tracks[${tracks_n},num]="${BASH_REMATCH[1]}"
		fi

		if [[ $line =~ $regex_sub ]]; then
			tracks[${tracks_n},sub]=1
		fi

		if [[ $line =~ $regex_lang ]]; then
			tracks[${tracks_n},lang]="${BASH_REMATCH[2]}"
		fi

		if [[ $line =~ $regex_name ]]; then
			tracks[${tracks_n},name]="${BASH_REMATCH[1]}"
		fi
	done

	tracks_n=$(( tracks_n + 1 ))

# Gets all subtitle tracks specifically.
	for (( i = 1; i < tracks_n; i++ )); do
		if [[ ${tracks[${i},sub]} -eq 1 ]]; then
			sub_tracks_n=$(( sub_tracks_n + 1 ))
		else
			continue
		fi

		sub_tracks[${sub_tracks_n},file]="$if_tmp"

		if [[ -n ${tracks[${i},num]} ]]; then
			sub_tracks[${sub_tracks_n},num]="${tracks[${i},num]}"
		fi

		if [[ -n ${tracks[${i},lang]} ]]; then
			if [[ -z ${sub_tracks[${sub_tracks_n},lang]} ]]; then
				sub_tracks[${sub_tracks_n},lang]="${tracks[${i},lang]}"
			fi
		fi

		if [[ -n ${tracks[${i},name]} ]]; then
			if [[ -z ${sub_tracks[${sub_tracks_n},name]} ]]; then
				sub_tracks[${sub_tracks_n},name]="${tracks[${i},name]}"
			fi
		fi
	done
}

# The loop below handles the arguments to the script.
while [[ -n $@ ]]; do
	case "$1" in
		'-lang')
			shift

			if [[ $1 =~ $regex_lang_arg ]]; then
				sub_tracks[${sub_tracks_n},lang]="${1,,}"
			else
				usage
			fi

			shift
		;;
		'-name')
			shift

			sub_tracks[${sub_tracks_n},name]="$1"

			shift
		;;
		*)
			if [[ -f $1 ]]; then
				get_tracks "$1"

				shift
			else
				usage
			fi
		;;
	esac
done

# If no subtitles have been found, quit.
if [[ ${#sub_tracks[@]} -eq 0 ]]; then
	usage
fi

# Adds 1 to $sub_tracks_n, so we can loop through all the elements.
# Otherwise, the last element will be skipped.
sub_tracks_n=$(( sub_tracks_n + 1 ))

# Prints all the subtitle tracks, and asks the user to choose the
# default track, saves that choice in the $default variable.
printf '\n%s\n\n' 'Choose the default track:'

for (( i = 1; i < sub_tracks_n; i++ )); do
	file_tmp="${sub_tracks[${i},file]}"
	lang_tmp="${sub_tracks[${i},lang]}"
	name_tmp="${sub_tracks[${i},name]}"

	printf '%s)\n' "$i"
	printf '  file: %s\n' "$file_tmp"
	printf '  language: %s\n' "$lang_tmp"
	printf '  name: %s\n' "$name_tmp"
done

printf '\n%s' '>'
read default

until [[ $default -lt $sub_tracks_n ]]; do
	printf '\n%s' '>'
	read default
done

printf '\nDefault subtitle track: %s\n' "$default"

if [[ -n ${sub_tracks[${default},num]} ]]; then
	printf '(Track ID: %s)\n\n' "${sub_tracks[${default},num]}"
fi

# Puts together the mkvmerge command. The loop below deals with
# subtitles that are in the Matroska file, and the subtitle files given
# as arguments to the script.
for (( i = 1; i < sub_tracks_n; i++ )); do
	file_tmp="${sub_tracks[${i},file]}"
	num_tmp="${sub_tracks[${i},num]}"
	lang_tmp="${sub_tracks[${i},lang]}"
	name_tmp="${sub_tracks[${i},name]}"

# If the current subtitle line belongs to the 1st file passed to the
# script (likely a Matroska file), then no need to carry on with the
# rest of the loop.
	if [[ $file_tmp == "${files[0]}" ]]; then
		if [[ $i -eq $default ]]; then
			args1+=('--default-track-flag' \""${num_tmp}:1"\")
		else
			args1+=('--default-track-flag' \""${num_tmp}:0"\")
		fi

		continue
	fi

	if [[ -n $lang_tmp ]]; then
		args2+=('--language' \""${num_tmp}:${lang_tmp}"\")
	fi

	if [[ -n $name_tmp ]]; then
		args2+=('--track-name' \""${num_tmp}:${name_tmp}"\")
	fi

	if [[ $i -eq $default ]]; then
		args2+=('--default-track-flag' \""${num_tmp}:1"\")
	else
		args2+=('--default-track-flag' \""${num_tmp}:0"\")
	fi

	if [[ -n $file_tmp ]]; then
		args2+=(\""${file_tmp}"\")
	fi
done

full_args=(mkvmerge -o \""$of"\" "${args1[@]}" \""$if"\" "${args2[@]}")

# Runs mkvmerge.
eval "${full_args[@]}"

# Removes temporary MKV files.
rm "${tmp_files[@]}"

# Prints the mkvmerge command.
string="${full_args[@]}"
printf '\n%s\n\n' "$string"
