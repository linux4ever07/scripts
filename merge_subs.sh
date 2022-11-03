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

files_n=0
sub_tracks_n=0
declare -a files files_tmp args full_args range1 range2
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

command -v mkvinfo 1>&- 2>&-

if [[ $? -ne 0 ]]; then
	printf '\nThis script needs %s installed!\n\n' 'mkvtoolnix'
	exit
fi

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
# add the file name to the 'files_tmp' array, so it can be deleted
# later.
	if [[ $ext_tmp != 'mkv' ]]; then
		mapfile -t mkvmerge_lines < <(mkvmerge -o "$of_tmp" "$if_tmp")

		if [[ $? -ne 0 ]]; then
			printf '%s\n' "${mkvmerge_lines[@]}"
			return
		fi

		files_tmp+=("$of_tmp")
		if_tmp="$of_tmp"
	fi

	files["${files_n}"]="$if_tmp"

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

			tracks["${tracks_n},sub"]=0
		fi

		if [[ $line =~ $regex_num ]]; then
			tracks["${tracks_n},num"]="${BASH_REMATCH[1]}"
		fi

		if [[ $line =~ $regex_sub ]]; then
			tracks["${tracks_n},sub"]=1
		fi

		if [[ $line =~ $regex_lang ]]; then
			tracks["${tracks_n},lang"]="${BASH_REMATCH[2]}"
		fi

		if [[ $line =~ $regex_name ]]; then
			tracks["${tracks_n},name"]="${BASH_REMATCH[1]}"
		fi
	done

	tracks_n=$(( tracks_n + 1 ))

# Gets all subtitle tracks specifically.
	for (( i = 1; i < tracks_n; i++ )); do
		sub_tmp="${tracks[${i},sub]}"
		num_tmp="${tracks[${i},num]}"
		lang_tmp="${tracks[${i},lang]}"
		name_tmp="${tracks[${i},name]}"

		if [[ $sub_tmp -eq 1 ]]; then
			sub_tracks_n=$(( sub_tracks_n + 1 ))
		else
			continue
		fi

		if [[ -n $num_tmp ]]; then
			sub_tracks["${sub_tracks_n},num"]="$num_tmp"
		fi

		if [[ -n $lang_tmp ]]; then
			if [[ -z ${sub_tracks[${sub_tracks_n},lang]} ]]; then
				sub_tracks["${sub_tracks_n},lang"]="$lang_tmp"
			fi
		fi

		if [[ -n $name_tmp ]]; then
			if [[ -z ${sub_tracks[${sub_tracks_n},name]} ]]; then
				sub_tracks["${sub_tracks_n},name"]="$name_tmp"
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
				sub_tracks["${sub_tracks_n},lang"]="${1,,}"
			else
				usage
			fi

			shift
		;;
		'-name')
			shift

			sub_tracks["${sub_tracks_n},name"]="$1"

			shift
		;;
		*)
			if [[ -f $1 ]]; then
				files_n=$(( files_n + 1 ))

				range1["${files_n}"]=$(( $sub_tracks_n + 1 ))
				get_tracks "$1"
				range2["${files_n}"]=$(( $sub_tracks_n + 1 ))

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

# Adds 1 to $files_n and $sub_tracks_n, so we can loop through all the
# elements. Otherwise, the last element will be skipped.
files_n=$(( files_n + 1 ))
sub_tracks_n=$(( sub_tracks_n + 1 ))

# Prints all the subtitle tracks, and asks the user to choose the
# default track, saves that choice in the $default variable.
printf '\n%s\n\n' 'Choose the default track:'

for (( i = 1; i < files_n; i++ )); do
	range1_tmp="${range1[${i}]}"
	range2_tmp="${range2[${i}]}"

	for (( j = range1_tmp; j < range2_tmp; j++ )); do
		lang_tmp="${sub_tracks[${j},lang]}"
		name_tmp="${sub_tracks[${j},name]}"

		printf '%s)\n' "$j"
		printf '  file: %s\n' "${files[${i}]}"
		printf '  language: %s\n' "$lang_tmp"
		printf '  name: %s\n' "$name_tmp"
	done
done

printf '\n%s' '>'
read default

until [[ $default -lt $sub_tracks_n ]]; do
	printf '\n%s' '>'
	read default
done

printf '\nDefault subtitle track: %s\n' "$default"
printf '(Track ID: %s)\n\n' "${sub_tracks[${default},num]}"

# Puts together the mkvmerge command. The loop below deals with
# subtitles that are in the Matroska file, and the subtitle files given
# as arguments to the script. The loop below makes sure a file name can
# only be listed once. This is for when a subtitle file has multiple
# subtitle tracks.
for (( i = 1; i < files_n; i++ )); do
	range1_tmp="${range1[${i}]}"
	range2_tmp="${range2[${i}]}"

	declare -a args_tmp

	for (( j = range1_tmp; j < range2_tmp; j++ )); do
		num_tmp="${sub_tracks[${j},num]}"
		lang_tmp="${sub_tracks[${j},lang]}"
		name_tmp="${sub_tracks[${j},name]}"

		if [[ $i -ne 1 ]]; then
			if [[ -n $lang_tmp ]]; then
				args_tmp+=('--language' \""${num_tmp}:${lang_tmp}"\")
			fi

			if [[ -n $name_tmp ]]; then
				args_tmp+=('--track-name' \""${num_tmp}:${name_tmp}"\")
			fi
		fi

		if [[ $j -eq $default ]]; then
			args_tmp+=('--default-track-flag' \""${num_tmp}:1"\")
		else
			args_tmp+=('--default-track-flag' \""${num_tmp}:0"\")
		fi
	done

	args_tmp+=(\""${files[${i}]}"\")
	args+=("${args_tmp[@]}")
	unset -v args_tmp
done

full_args=(mkvmerge -o \""$of"\" "${args[@]}")

# Runs mkvmerge.
eval "${full_args[@]}"

# Removes temporary MKV files.
if [[ -n ${files_tmp[@]} ]]; then
	rm "${files_tmp[@]}"
fi

# Prints the mkvmerge command.
string="${full_args[@]}"
printf '\n%s\n\n' "$string"
