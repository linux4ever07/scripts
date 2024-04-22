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

declare session default files_n sub_tracks_n range1_tmp range2_tmp string
declare sub_tmp num_tmp lang_tmp name_tmp
declare -a cmd files files_tmp args full_args range1 range2
declare -A if of regex sub_tracks

session="${RANDOM}-${RANDOM}"

if[fn]=$(readlink -f "$1")
of[fn]="${if[fn]%.*}-${session}.mkv"

regex[start]='^\|\+ Tracks$'
regex[stop]='^\|\+ '
regex[strip]='^\| +\+ (.*)$'
regex[track]='^Track$'
regex[num]='^Track number: [0-9]+ \(track ID for mkvmerge & mkvextract: ([0-9]+)\)$'
regex[sub]='^Track type: subtitles$'
regex[lang]='^Language( \(.*\)){0,1}: (.*)$'
regex[name]='^Name: (.*)$'

regex[fn]='^(.*)\.([^.]*)$'
regex[lang_arg]='^[[:alpha:]]{3}$'

files_n=0
sub_tracks_n=0

mapfile -t cmd < <(command -v mkvinfo mkvmerge)

if [[ ${#cmd[@]} -ne 2 ]]; then
	printf '\nThis script needs %s installed!\n\n' 'mkvtoolnix'
	exit
fi

# Creates a function, called 'usage', which will print usage
# instructions and then quit.
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

# Creates a function, called 'run_cmd', which will be used to run
# external commands, capture their output, and print the output (and
# quit) if the command fails.
run_cmd () {
	declare exit_status
	declare -a cmd_stdout

	mapfile -t cmd_stdout < <(eval "$@" 2>&1; printf '%s\n' "$?")

	exit_status="${cmd_stdout[-1]}"
	unset -v cmd_stdout[-1]

# Prints the output from the command if it has a non-zero exit status,
# and then quits.
	if [[ $exit_status != '0' ]]; then
		printf '%s\n' "${cmd_stdout[@]}"
		printf '\n'
		exit
	fi
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

# Creates a function, called 'get_tracks', which will read the metadata
# of media files, and if they contain subtitle tracks, store those in
# the 'sub_tracks' hash.
get_tracks () {
	if[fn_tmp]=$(readlink -f "$1")
	if[bn_tmp]=$(basename "${if[fn_tmp]}")
	if[dn_tmp]=$(dirname "${if[fn_tmp]}")

	declare fn_tmp ext_tmp session_tmp switch tracks_n line
	declare -a mkvinfo_lines mkvinfo_tracks
	declare -A tracks

# Parses the input file name, and separates basename from extension.
# If this fails, return from the function.
	if [[ ${if[bn_tmp],,} =~ ${regex[fn]} ]]; then
		fn_tmp="${BASH_REMATCH[1]}"
		ext_tmp="${BASH_REMATCH[2]}"
		session_tmp="${RANDOM}-${RANDOM}"

		of[fn_tmp]="${if[dn_tmp]}/${fn_tmp}-tmp-${session_tmp}.mkv"
	else
		return
	fi

# If input file is not a Matroska file, remux it to a temporary MKV,
# add the file name to the 'files_tmp' array, so it can be deleted
# later.
	if [[ $ext_tmp != 'mkv' ]]; then
		printf '\nRemuxing: %s\n' "${if[fn_tmp]}"

		run_cmd mkvmerge -o \""${of[fn_tmp]}"\" \""${if[fn_tmp]}"\"

		files_tmp+=("${of[fn_tmp]}")

		if[fn_tmp]="${of[fn_tmp]}"
	fi

# Adds file name to the 'files' array, so it can be used later to
# construct the mkvmerge command.
	files["${files_n}"]="${if[fn_tmp]}"

	mapfile -t mkvinfo_lines < <(mkvinfo "${if[fn_tmp]}" 2>&-)

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

# Gets all tracks from Matroska file.
	tracks_n=0

	for (( i = 0; i < ${#mkvinfo_tracks[@]}; i++ )); do
		line="${mkvinfo_tracks[${i}]}"

		if [[ $line =~ ${regex[track]} ]]; then
			(( tracks_n += 1 ))
			tracks["${tracks_n},sub"]=0
		fi

		if [[ $line =~ ${regex[num]} ]]; then
			tracks["${tracks_n},num"]="${BASH_REMATCH[1]}"
		fi

		if [[ $line =~ ${regex[sub]} ]]; then
			tracks["${tracks_n},sub"]=1
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

# Gets all subtitle tracks specifically.
	for (( i = 1; i < tracks_n; i++ )); do
		sub_tmp="${tracks[${i},sub]}"
		num_tmp="${tracks[${i},num]}"
		lang_tmp="${tracks[${i},lang]}"
		name_tmp="${tracks[${i},name]}"

		if [[ $sub_tmp -eq 1 ]]; then
			(( sub_tracks_n += 1 ))
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
while [[ $# -gt 0 ]]; do
	case "$1" in
		'-lang')
			shift

			if [[ $1 =~ ${regex[lang_arg]} ]]; then
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
				(( files_n += 1 ))

				range1["${files_n}"]=$(( sub_tracks_n + 1 ))
				get_tracks "$1"
				range2["${files_n}"]=$(( sub_tracks_n + 1 ))

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
(( files_n += 1 ))
(( sub_tracks_n += 1 ))

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

printf '\n'

until [[ -n $default ]]; do
	read -p '>'

	if [[ ! $REPLY =~ ^[0-9]+$ ]]; then
		continue
	fi

	if [[ -n ${sub_tracks[${REPLY},num]} ]]; then
		default="$REPLY"
	fi
done

printf '\nDefault subtitle track: %s\n' "$default"
printf '(Track ID: %s)\n\n' "${sub_tracks[${default},num]}"

# Puts together the mkvmerge command. The loop below deals with
# subtitles that are in the Matroska file, and the subtitle files given
# as arguments to the script. The loop makes sure a file name can only
# be listed once. This is for when a subtitle file has multiple subtitle
# tracks.
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

full_args=(mkvmerge -o \""${of[fn]}"\" "${args[@]}")

# Runs mkvmerge.
eval "${full_args[@]}"

# Removes temporary MKV files.
clean_up

# Prints the mkvmerge command.
string="${full_args[@]}"
printf '\n%s\n\n' "$string"
