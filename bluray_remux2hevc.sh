#!/bin/bash

# Usage: bluray_remux2hevc.sh [mkv|m2ts] -out [directory] [...]

# This script will:
# * Parse the input filename (a 1080p BluRay (remux or full)), get movie
# info from IMDb, incl. name and year.
# * Extract core DTS track from DTS-HD MA track (with ffmpeg).
# * Remux the input file (MKV or M2TS), without all its audio tracks,
# with the extracted core DTS track (with ffmpeg).
# * Encode the remuxed MKV to HEVC / x265 in HandBrake.
# * Merge the finished encode with the subtitles from the source file.
# * Create info txt files for input, output, and remux output.

# The input file should be a Blu-Ray remux, that has identical bitrate
# to the original Blu-Ray disc, for the video and audio tracks.
# As an example, this is the video bitrate of
# the "The Imaginarium of Doctor Parnassus (2009)" Blu-Ray:
# 29495915 b/s = 29495.915 kb/s = 29.495915 mb/s

# Output bitrate:
# HEVC video track: 5000 kb/s
# DTS audio track: 1536 kb/s
# video track + audio track = 6536 kilobits / s
# kilobits to kilobytes: 817 kilobytes / s

# So, you need to know the length of the input video in order to
# figure out how large the output file will be:
# seconds * bitrate = output size

# The subtitles will add a bit of extra size.

# First argument to this script should be a file, for example an
# M2TS or MKV.
# '-grain' and '-anime' tell the script whether or not to use the
# '--encoder-tune grain' or '--encoder-tune anime' HandBrake argument.
# -grain is only needed if the input video has film grain (all movies
# shot on analog film have grain). -anime is only needed if the input
# video is any kind of animation.

# Attention:

# It's recommended to run this script in a background TTY.
# For example: TTY4 (Ctrl + Alt + F4)

# Because then HandBrake can be remotely paused from the desktop:

# kill -s 20 PID

# And then resumed:

# kill -s 18 PID

# This script finishes as it's supposed to.

# The HandBrake PID can be found by running:
# ps -C HandBrakeCLI -o pid,args

# One more thing...

# Make sure you have enough free space in the output directory.
# The output, and remux output, files are quite large.

# The script was first created in 2019.

# Generates a random number, which can be used for these filenames:
# dts track, output, output remux, input info txt, output info txt,
# output remux info txt.
session="$RANDOM"

# Creates a variable that will contain the exit status of all
# commands run in the script.
exit_status=0

# Creates a variable that will work as a switch. If this variable is set
# to '1', it will skip running the 'dts_extract_remux' and 'remux_mkv'
# functions. This is handy if that file has already been created in
# a previous session of this script.
exist=0

# Creates a variable that will work as a switch. If this variable is set
# to '1', it will use pass the subtitles from the input file to
# HandBrake. This is to prevent the subtitles from going out of sync
# with the audio and video, when dealing with input files that have
# been merged from multiple BluRay discs.
hb_subs=0

# Sets the default language to English. This language code is what
# the script till look for when extracting the core DTS track.
lang='eng'

anime=0
grain=0

# Gets full path of input file.
if=$(readlink -f "$1")
bname=$(basename "$if")

# Creates a function called 'usage', which prints the syntax,
# some basic info, and quits.
usage () {
	cat <<USAGE

Usage: $(basename "$0") [mkv|m2ts] -out [directory] [...]

This script encodes an input MKV or M2TS Blu-Ray remux to HEVC / x265.

The input file should be a Blu-Ray remux, that has identical bitrate
to the original Blu-Ray disc, for the video and audio tracks.
As an example, this is the video bitrate of
the "The Imaginarium of Doctor Parnassus (2009)" Blu-Ray:
29495915 b/s = 29495.915 kb/s = 29.495915 mb/s

	Optional arguments:

-lang [code]
	Three-letter language code for the audio track.

-exist
	In case the output remux file already exists.

-hb_subs
	Pass the subs directly to HandBrake instead of ffmpeg.

-anime
	Only needed if the input file is animation.

-grain
	Only needed if the input file has film grain.

	Attention:

It's recommended to run this script in a background TTY.
For example: TTY4 (Ctrl + Alt + F4)

Because then HandBrake can be remotely paused from the desktop:

kill -s 20 PID

And then resumed:

kill -s 18 PID

This script finishes as it's supposed to.

The HandBrake PID can be found by running:
ps -C HandBrakeCLI -o pid,args

USAGE
	exit
}

# Creates a function called 'is_torrent', which checks if the filename
# ends with '.part', or if there's a filename in the same directory that
# ends with '.part'. If there is, wait until the filename changes, and
# '.part' is removed from the filename. This function recognizes if
# input file is an unfinished download, and waits for the file to fully
# download before processing it.
is_torrent () {
	if [[ $if =~ .part$ ]]; then
		if_tmp="$if"
	else
		if_tmp="${if}.part"
	fi

	if [[ -f $if_tmp ]]; then
		printf '\n%s\n' 'Waiting for this download to finish:'
		printf '%s\n\n' "${if_tmp}"

		while [[ -f $if_tmp ]]; do
			sleep 5
		done

		if="${if%.part}"

		md5=$(md5sum -b "$if")
		md5_f="${HOME}/${bname}_MD5-${RANDOM}.txt"

		printf '%s\r\n' "$md5" | tee "$md5_f"
	fi
}

is_torrent

# If first argument is empty, or is not a real file, then print
# syntax and quit.
if [[ -z $1 || ! -f $if ]]; then
	usage
fi

# The loop below handles the arguments to the script.
shift

while [[ ${#@} -gt 0 ]]; do
	case $1 in
		'-out')
			shift

			if [[ ! -d $1 ]]; then
				usage
			else
				of_dir=$(readlink -f "$1")
			fi

			shift
		;;
		'-lang')
			shift

			lang_regex='[[:alpha:]]{3}'

			if [[ ! $1 =~ $lang_regex ]]; then
				usage
			else
				lang=$(tr '[:upper:]' '[:lower:]' <<<"$1")
			fi

			shift
		;;
		'-exist')
			shift

			exist=1
		;;
		'-hb_subs')
			shift

			hb_subs=1
		;;
		'-anime')
			shift

			if [[ $grain -eq 1 ]]; then
				usage
			fi

			anime=1
		;;
		'-grain')
			shift

			if [[ $anime -eq 1 ]]; then
				usage
			fi

			grain=1
		;;
		*)
			usage
		;;
	esac
done

if [[ -z $of_dir ]]; then
	usage
fi

# Creates an array of the list of commands needed by this script.
cmd=(HandBrakeCLI ffmpeg mkvmerge curl flac)

# Declares an associative array (hash), which contains the package names
# of the commands that are needed by the script.
declare -A pkg
pkg[${cmd[0]}]='HandBrake'
pkg[${cmd[1]}]='ffmpeg'
pkg[${cmd[2]}]='mkvtoolnix'
pkg[${cmd[3]}]='curl'
pkg[${cmd[4]}]='flac'

# Checks if HandBrake, ffmpeg, mkvtoolnix and curl are available on
# this system. If not, display a message, and quit.
for cmd_tmp in "${cmd[@]}"; do
	check=$(basename $(command -v ${cmd_tmp}) 2>&-)

	if [[ -z $check ]]; then
		printf '\n%s\n' "You need ${pkg[${cmd_tmp}]} installed on your system."
		printf '%s\n\n' 'Install it through your package manager.'
		exit
	fi
done

# Setting some variables that will be used to create a full HandBrake
# command, with args.
format='av_mkv'
v_encoder='x265_10bit'
preset='slow'
v_bitrate=5000
a_encoder='copy:dts'

# Creates a variable which contains the last part of the output
# filename.
rls_type='1080p.BluRay.x265.DTS'

# This creates a function called 'fsencode', which will delete special
# characters that are not allowed in filenames on certain filesystems.
# The characters in the regex are allowed. All others are deleted. Based
# on the "POSIX fully portable filenames" entry:
# https://en.wikipedia.org/wiki/Filename#Comparison_of_filename_limitations
fsencode () {
	sed 's/[^ A-Za-z0-9._-]//g' <<<"$1"
}

# This creates a function called 'uriencode', which will translate
# the special characters in any string to be URL friendly. This will be
# used in the 'imdb' function.
uriencode () {
	curl -Gso /dev/null -w %{url_effective} --data-urlencode @- "" <<<"${@}" | sed -E 's/..(.*).../\1/'
}

# This creates a function called 'break_name', which will break up
# the input filename, and parse it, to extract the movie name, and year.
break_name () {
# Sets $bname to the first argument passed to this function.
	bname="$1"

	declare -a name

	types=('dots' 'hyphens' 'underscores' 'spaces')

	regex='^(.*)([[:punct:]]|[[:space:]]){1,}([0-9]{4})([[:punct:]]|[[:space:]]){1,}(.*)$'

# If $temp can't be parsed, set it to the input filename instead,
# although limit the string by 64 characters, and remove possible
# trailing whitespace from the string.
	if [[ $bname =~ $regex ]]; then
		temp=$(sed -E "s/${regex}/\1/" <<<"$bname")
		year=$(sed -E "s/${regex}/\(\3\)/" <<<"$bname")
	else
		temp=$(sed 's/ *$//' <<<"${bname:0:64}")
	fi

# Break $bname up in a list of words, and store those words in arrays,
# depending on whether $bname is separated by dots, hyphens,
# underscores or spaces.
	mapfile -d'.' -t bname_dots <<<"$temp"
	mapfile -d'-' -t bname_hyphens <<<"$temp"
	mapfile -d'_' -t bname_underscores <<<"$temp"
	mapfile -d' ' -t bname_spaces <<<"$temp"

# Declares an associative array (hash), that stores the element numbers
# for each kind of word separator: dots, hyphens, underscores, spaces.
	declare -A bname_elements
	bname_elements[dots]=${#bname_dots[@]}
	bname_elements[hyphens]=${#bname_hyphens[@]}
	bname_elements[underscores]=${#bname_underscores[@]}
	bname_elements[spaces]=${#bname_spaces[@]}

# If there are more dots in $bname than hyphens, underscores or spaces,
# that means $bname is separated by dots. Otherwise, it's separated by
# hyphens, underscores or spaces. In either case, loop through the word
# list in either array, and break the name up in separate words. The
# last element is the year, so do a regex on that to filter out other
# characters besides four digits.

	elements=0

# This for loop is to figure out if $bname is separated by dots,
# hyphens, underscores or spaces.
	for type in "${types[@]}"; do
		temp_number="bname_elements[${type}]"

		if [[ ${!temp_number} -gt $elements ]]; then
			elements="${!temp_number}"
			temp_type="$type"
		fi
	done

# This for loop is to go through the word list.
	for (( i = 0; i < $elements; i++ )); do
# Creates a reference, pointing to the $i element of the
# 'bname_$temp_type' array.
		array_ref="bname_${temp_type}[${i}]"

		name[${i}]=$(tr -d '[:space:]' <<<"${!array_ref}")
	done

	if [[ ! -z $year ]]; then
		name+=("$year")
	fi

# Prints the complete parsed name.
	name_string=$(sed -E 's/ +/ /g' <<<"${name[@]}")
	printf '%s\n' "$name_string"
}

# This creates a function called 'imdb', which will look up the movie
# name on IMDb, based on the file name of the input file.
# https://www.imdb.com/search/title/
# https://www.imdb.com/interfaces/
imdb () {
	term="${@}"
	t_y_regex='^(.*) \(([0-9]{4})\)$'
	id_regex='\/title\/(tt[0-9]+)'
	title_regex1='\,\"originalTitleText\":'
	title_regex2='\"text\":\"(.*)\"\,\"__typename\":\"TitleText\"'
	year_regex1='\,\"releaseYear\":'
	year_regex2='\"year\":([0-9]{4})\,\"endYear\":.*\,\"__typename\":\"YearRange\"'
	plot_regex1='\"plotText\":'
	plot_regex2='\"plainText\":\"(.*)\"\,\"__typename\":\"Markdown\"'
	rating_regex1='\,\"ratingsSummary\":'
	rating_regex2='\"aggregateRating\":(.*)\,\"voteCount\":.*\,\"__typename\":\"RatingsSummary\"'
	genre_regex1='\"genres\":\['
	genre_regex2='\"text\":\"(.*)\"\,\"id\":\".*\"\,\"__typename\":\"Genre\"'
	director_regex1='\]\,\"director\":\['
	director_regex2='\"@type\":\"Person\",\"url\":\".*\"\,\"name\":\"(.*)\"'
	runtime_regex1='\,\"runtime\":'
	runtime_regex2='\"seconds\":(.*)\,\"__typename\":\"Runtime\"'

	agent='Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/103.0.0.0 Safari/537.36'

	get_page () {
		curl --location --user-agent "${agent}" --retry 10 --retry-delay 10 --connect-timeout 10 --silent "${1}" 2>&-
	}

	if [[ $# -eq 0 ]]; then
		printf '%s\n\n' 'Usage: imdb "movie title (year)"'
		return 1
	else
		t=$(uriencode "$(sed -E "s/${t_y_regex}/\1/" <<<"${term}")")

		if [[ $term =~ $t_y_regex ]]; then
			y=$(sed -E "s/${t_y_regex}/\2/" <<<"${term}")
		fi
	fi

# Sets the type of IMDb search results to include.
	type='feature,tv_movie,tv_special,documentary,video'

# If the $y variable is empty, that means the year is unknown, hence we
# will need to use slightly different URLs, when searching for the
# movie.
	if [[ -z $y ]]; then
		url_tmp="https://www.imdb.com/search/title/?title=${t}&title_type=${type}&view=simple"
	else
		url_tmp="https://www.imdb.com/search/title/?title=${t}&title_type=${type}&release_date=${y},${y}&view=simple"
	fi

	mapfile -t id_array < <(get_page "${url_tmp}" | grep -Eo "${id_regex}" | sed -E "s/${id_regex}/\1/")
	id="${id_array[0]}"

	if [[ -z $id ]]; then
		return 1
	fi

	url="https://www.imdb.com/title/${id}/"

# Translate {} characters to newlines so we can parse the JSON data.
# I came to the conclusion that this is the most simple, reliable and
# future-proof way to get the movie information. It's possible to add
# more regex:es to the for loop below, to get additional information.
# Excluding lines that are longer than 500 characters, to make it
# slightly faster.
	mapfile -t tmp_array < <(get_page "${url}" | tr '{}' '\n' | grep -Ev -e '.{500}' -e '^$')

	n=0

	declare -A json_types

	json_types=(['title']=1 ['year']=1 ['plot']=1 ['rating']=1 ['genre']=1 ['director']=1 ['runtime']=1)

	for (( z = 0; z < ${#tmp_array[@]}; z++ )); do
		for json_type in "${!json_types[@]}"; do
			json_regex1_ref="${json_type}_regex1"
			json_regex2_ref="${json_type}_regex2"

			if [[ "${tmp_array[${z}]}" =~ ${!json_regex1_ref} ]]; then
				n=$(( z + 1 ))
				eval ${json_type}=\"$(sed -E "s/${!json_regex2_ref}/\1/" <<<"${tmp_array[${n}]}")\"
				unset -v json_types[${json_type}]
				break
			fi
		done
	done

	printf '%s\n' "$title"
	printf '%s\n' "$year"

	unset -v title year plot rating genre director runtime
}

# Creates a function called 'dts_extract_remux', which will find a
# DTS-HD MA track (if it exists), with the same language code as in
# $lang. If this track is found, extract the core DTS track from it.
# If there's no DTS-HD MA, it will pick either TrueHD, PCM, FLAC, DTS or
# AC3 (in that order, if they exist). The output will still be DTS
# regardless. This function also tries to figure out the appropriate
# output audio bitrate, by looking at the metadata of the input file,
# and finding the audio bitrate there. There are two choices for output
# audio bitrate, 768 kb/s and 1536 kb/s. This function will also remux
# the input file, without all its audio tracks but with the video and
# subtitle tracks, and with the core DTS track.
dts_extract_remux () {
	regex_audio="^ +Stream #.*(\(${lang}\)){0,1}: Audio: "
	regex_51=', 5.1\(.*\),'
	bps_regex='^ +BPS.*: [0-9]+'
	bps_regex2='[0-9]{3}'
	bps_regex3='.* ([0-9]+) kb/s$'
	bps_regex4='^.*: ([0-9]+)'
	bps_regex5='.*(...)$'
	kbps_regex='[0-9]+ kb/s$'
	map_regex='.*Stream #(0:[0-9]+).*'

	high_kbps='1536'
	low_kbps='768'
	high_bps='1537000'
	low_bps='769000'
	bps_limit=$(( (high_bps - low_bps) / 2 ))
	use_kbps="${high_kbps}k"

	declare -A type elements
	type[dts_hdma]='dts \(DTS-HD MA\)'
	type[truehd]='truehd'
	type[pcm]='pcm_bluray'
	type[flac]='flac'
	type[dts]='dts \(DTS(-ES)?\)'
	type[ac3]='ac3'
	elements[dts_hdma]=0
	elements[truehd]=0
	elements[pcm]=0
	elements[flac]=0
	elements[dts]=0
	elements[ac3]=0

	audio_types=(dts_hdma truehd pcm flac dts ac3)

	declare -A audio_tracks

	get_bitrate () {
		first_line_regex='^ +Metadata:'
		last_line_regex='^ +Stream #'

		compare_bitrate () {
# If $high_bps (the maximum DTS bitrate) is greater than $bps_if,
# then...
			if [[ $high_bps -gt $bps_if ]]; then
# Gets the exact difference between max DTS bitrate and input bitrate.
				bps_diff=$(( high_bps - bps_if ))

# If the difference is greater than $bps_limit, then set the $use_kbps
# variable to $low_kbps.
				if [[ $bps_diff -ge $bps_limit ]]; then
					use_kbps="${low_kbps}k"
				fi
			fi
		}

# If $audio_format is 'flac', we will decode the FLAC audio track in
# order to get the correct (uncompressed) bitrate, which will later be
# used to calculate the output bitrate. This is the part where we set
# the $audio_track_tmp variable, which will be used later in this
# function to find the bitrate.
		if [[ $audio_format == 'flac' ]]; then
			regex_flac="^ +Stream #.*: Audio: "

			flac_tmp="${of_dir}/FLAC.TMP-${session}.flac"
			wav_tmp="${of_dir}/FLAC.TMP-${session}.wav"

# Gets the ffmpeg map code of the FLAC track.
			map_tmp=$(sed -E 's/.*Stream #(0:[0-9]+).*/\1/' <<<"${!audio_track_ref}")

# Extracts the FLAC track from $if, and decodes it to WAV.
			eval ${cmd[1]} -i \""${if}"\" -map ${map} -c:a copy \""$flac_tmp"\"
			eval ${cmd[4]} -d \""$flac_tmp"\"
			rm "$flac_tmp"

# Gets information about the WAV file.
			mapfile -t flac_info < <(eval ${cmd[1]} -hide_banner -i \""${wav_tmp}"\" 2>&1)
			rm "$wav_tmp"

# Go through the information about the input file, and see if any of the
# lines are audio, and if they match the type of audio we're looking
# for.
			for (( i = 0; i < ${#flac_info[@]}; i++ )); do
# See if the current line is an audio track.
				if [[ ${flac_info[${i}]} =~ $regex_flac ]]; then
					audio_track_tmp="${flac_info[${i}]}"
					if_info_tmp=("${flac_info[@]}")
					break
				fi
			done
		else
			audio_track_tmp="${!audio_track_ref}"
			if_info_tmp=("${if_info[@]}")
		fi

# If the $audio_track_tmp line contains a bitrate, use that and
# compare it against the $bps_limit variable.
		if [[ $audio_track_tmp =~ $kbps_regex ]]; then
			bps_if=$(sed -E "s|${bps_regex3}|\1|" <<<"${audio_track_tmp}")
			bps_if=$(( bps_if * 1000 ))

			compare_bitrate
			return
		fi

# This loop looks for the line number of $audio_track_tmp...
		for (( i = 0; i < ${#if_info_tmp[@]}; i++ )); do
			if [[ ${if_info_tmp[${i}]} == $audio_track_tmp ]]; then
				j=$(( i + 1 ))
				break
			fi
		done

# If line matches $first_line_regex, continue looking for the bitrate in
# the metadata.
		if [[ ${if_info_tmp[${j}]} =~ $first_line_regex ]]; then
			for (( i = ${j}; i < ${#if_info_tmp[@]}; i++ )); do
# If line matches $last_line_regex, break this loop.
				if [[ ${if_info_tmp[${i}]} =~ $last_line_regex ]]; then
					break
				fi

# If line matches $bps_regex...
				if [[ ${if_info_tmp[${i}]} =~ $bps_regex ]]; then
# Deletes everything on the line, except the number of bytes per second
# (BPS).
					bps_if=$(sed -E "s/${bps_regex4}/\1/" <<<"${if_info_tmp[${i}]}")

# If input bitrate consists of at least 3 digits...
					if [[ $bps_if =~ $bps_regex2 ]]; then
# Gets the 3 last digits of the input bitrate.
						bps_last=$(sed -E -e "s/${bps_regex5}/\1/" -e 's/^0*//' <<<"$bps_if")

# If the last 3 digits are equal to (or higher than) 500, then round up
# that number, otherwise round it down.
						if [[ $bps_last -ge 500 ]]; then
							bps_if=$(( (bps_if - bps_last) + 1000 ))
						else
							bps_if=$(( bps_if - bps_last ))
						fi
					fi

					compare_bitrate
					break
				fi
			done
		fi
	}

# Go through the information about the input file, and see if any of the
# lines are audio, and if they match the types of audio we're looking
# for.
	for (( i = 0; i < ${#if_info[@]}; i++ )); do
# See if the current line is an audio track, and the same language as
# $lang.
		if [[ ${if_info[${i}]} =~ $regex_audio ]]; then
			for tmp_type in ${audio_types[@]}; do
				n="elements[${tmp_type}]"

				if [[ ${if_info[${i}]} =~ ${type[${tmp_type}]} ]]; then
					if [[ ${!audio_tracks[@]} -eq 0 ]]; then
						audiotracks[$tmp_type]="${if_info[${i}]}"
					fi

					audio_tracks[${tmp_type},${!n}]="${if_info[${i}]}"
					elements[${tmp_type}]=$(( ${!n} + 1 ))
				fi
			done
		fi
	done

	switch=0

# Go through the different types of audio and see if we have a matching
# 5.1 track in one of those formats. If not, use the first track in the
# list, in the preferred available format.
	for tmp_type in ${audio_types[@]}; do
		for (( i = 0; i < ${elements[${tmp_type}]}; i++ )); do
			array_ref="audio_tracks[${tmp_type},${i}]"

			if [[ ${!array_ref} =~ $regex_51 ]]; then
				audio_track_ref="audio_tracks[${tmp_type},${i}]"
				audio_format="$tmp_type"
				switch=1
				break
			fi
		done

		if [[ $switch -eq 1 ]]; then
			break
		fi
	done

# Pick the first audio track in the list, if $audio_track_ref is still
# empty.
	if [[ -z $audio_track_ref ]]; then
		for tmp_type in ${audio_types[@]}; do
			if [[ ${elements[${tmp_type}]} -gt 0 ]]; then
				audio_track_ref="audio_tracks[${tmp_type},0]"
				audio_format="$tmp_type"
				break
			fi
		done

		if [[ -z $audio_track_ref ]]; then
			for tmp_type in ${audio_types[@]}; do
					audio_track_ref="audio_tracks[${tmp_type}]"
					audio_format="$tmp_type"
					break
			done
		fi
	fi

	if [[ -z $audio_track_ref ]]; then
		printf '\n%s\n\n' 'There are no DTS-HD MA audio tracks in:'
		printf '%s\n\n' "$if"
		printf '%s\n' 'Choose a different input file that has DTS-HD MA!'
		exit
	fi

# Gets the ffmpeg map code of the audio track.
	map=$(sed -E "s/${map_regex}/\1/" <<<"${!audio_track_ref}")

# Creates first part of ffmpeg command.
	args1=(${cmd[1]} -i \""${if}"\" -metadata title=\"\" -map 0:v -map ${map} -map 0:s?)

# Creates ffmpeg command.
	case $audio_format in
		'dts_hdma')
			args=("${args1[@]}" -bsf:a dca_core -c:v copy -c:a copy -c:s copy \""${of_remux}"\")
		;;
		'truehd')
			args=("${args1[@]}" -strict -2 -c:v copy -c:a dts -c:s copy -ab ${use_kbps} \""${of_remux}"\")
		;;
		'pcm')
			get_bitrate
			args=("${args1[@]}" -strict -2 -c:v copy -c:a dts -c:s copy -ab ${use_kbps} \""${of_remux}"\")
		;;
		'flac')
			get_bitrate
			args=("${args1[@]}" -strict -2 -c:v copy -c:a dts -c:s copy -ab ${use_kbps} \""${of_remux}"\")
		;;
		'dts')
			args=("${args1[@]}" -c:v copy -c:a copy -c:s copy \""${of_remux}"\")
		;;
		'ac3')
			get_bitrate
			args=("${args1[@]}" -strict -2 -c:v copy -c:a dts -c:s copy -ab ${use_kbps} \""${of_remux}"\")
		;;
	esac

# Runs ffmpeg, extracts the core DTS track, and remuxes.
	args_string="${args[@]}"
	printf '\r\n%s\r\n' 'Command used to extract core DTS track, and remux:' | tee --append "$command_f"
	printf '%s\r\n' "$args_string" | tee --append "$command_f"

	if [[ $exist -ne 1 ]]; then
# Runs ffmpeg. If the command wasn't successful, quit.
		run_or_quit
	fi
}

# Creates a function called 'hb_encode', which will generate a full
# HandBrake command (with args), and then execute it.
hb_encode () {
	args1=(${cmd[0]} --format $format --markers --encoder $v_encoder --encoder-preset ${preset})

	if [[ $hb_subs -eq 1 ]]; then
		args2=(--vb $v_bitrate --two-pass --vfr --aencoder $a_encoder --all-subtitles -i \""${of_remux}"\" -o \""${of}"\")
	else
		args2=(--vb $v_bitrate --two-pass --vfr --aencoder $a_encoder -i \""${of_remux}"\" -o \""${of}"\")
	fi

	args3=(2\> \>\(tee \""${hb_log_f}"\"\))

	grain_tune='--encoder-tune grain'
	anime_tune='--encoder-tune animation'

# Creates the HandBrake command, which will be used to encode the input
# file to a HEVC output file. Depending on whether $grain is set to 1 or
# 0, we get a different HandBrake command.
	if [[ $grain -eq 1 ]]; then
		args=("${args1[@]}" "${grain_tune}" "${args2[@]}" "${args3[@]}")
	elif [[ $anime -eq 1 ]]; then
		args=("${args1[@]}" "${anime_tune}" "${args2[@]}" "${args3[@]}")
	else
		args=("${args1[@]}" "${args2[@]}" "${args3[@]}")
	fi

# Prints the full HandBrake command, and executes it.
	args_string="${args[@]}"
	printf '\r\n%s\r\n' 'Command used to encode:' | tee --append "$command_f"
	printf '%s\r\n' "$args_string" | tee --append "$command_f"

# Runs HandBrake. If the command wasn't successful, quit.
	run_or_quit
}

# Creates a function called 'sub_mux', which will remux the finished
# encode with the subtitles from $of_remux.
sub_mux () {
	mapfile -t if_subs < <(mkvinfo "${of_remux}" 2>&- | grep 'Track type: subtitles')

	if [[ -z ${if_subs[0]} ]]; then
		return
	fi

	args=(${cmd[2]} --title \"\" -o \""${of_tmp}"\" \""${of}"\" --no-video --no-audio --no-chapters \""${of_remux}"\")

	args_string="${args[@]}"
	printf '\r\n%s\r\n' 'Commands used to merge with subtitles:' | tee --append "$command_f"
	printf '%s\r\n' "$args_string" | tee --append "$command_f"

	run_or_quit

	args=(mv \""${of_tmp}"\" \""${of}"\")

	args_string="${args[@]}"
	printf '\r\n%s\r\n' "$args_string" | tee --append "$command_f"

	run_or_quit
}

# Creates a function called 'info_txt', which creates info txt files
# containing information generated by ffmpeg. It creates a separate
# txt file for input file, output file and remux output.
# If the mediainfo command is installed, a text file containing
# information from that will also be created.
info_txt () {
# Creates the basename of $of and $of_remux.
	of_bname=$(basename "$of")
	of_remux_bname=$(basename "$of_remux")

	cmd[5]=$(basename $(command -v mediainfo) 2>&-)

# Creates filenames for the info txt files, which contain the
# information generated by 'ffmpeg'. Also creates filenames for
# HandBrake version and options, and filenames for ffmpeg version and
# options.
	if_info_f="${info_dir}/${bname}_info.txt"
	of_info_f="${info_dir}/${of_bname}_info.txt"
	of_remux_info_f="${info_dir}/${of_remux_bname}_info.txt"
	hb_version_info_f="${info_dir}/${cmd[0]}_version.txt"
	hb_opts_info_f="${info_dir}/${cmd[0]}_options.txt"
	ff_version_info_f="${info_dir}/${cmd[1]}_version.txt"
	ff_opts_info_f="${info_dir}/${cmd[1]}_options.txt"
	size_info_f="${info_dir}/size.txt"
	mediainfo_info_f="${info_dir}/${bname}_mediainfo.txt"

	if [[ ${cmd[5]} ]]; then
		info_list_1=(if_info of_info of_remux_info mediainfo_info)
	else
		info_list_1=(if_info of_info of_remux_info)
	fi

	info_list_2=(hb_version_info hb_opts_info ff_version_info ff_opts_info size_info)
	info_list_3=(${info_list_1[@]} ${info_list_2[@]})

# If the info txt filenames (in list 1) already exist, add a random
# number to the end of the filename. Also, create empty files with those
# names.
	for txt_f in ${info_list_1[@]}; do
		txt_ref="${txt_f}_f"

		if [[ -f ${!txt_ref} ]]; then
			txt_tmp="${!txt_ref%.txt}"

			eval ${txt_f}_f="${txt_tmp}-${session}.txt"
		fi

		touch "${!txt_ref}"
	done

# If the info txt filenames (in list 2) already exist, remove them.
# Also, create empty files with those names.
	for txt_f in ${info_list_2[@]}; do
		txt_ref="${txt_f}_f"

		if [[ -f ${!txt_ref} ]]; then
			rm "${!txt_ref}"
		fi

		touch "${!txt_ref}"
	done

# Gets information about output file.
	mapfile -t of_info < <(eval ${cmd[1]} -hide_banner -i \""${of}"\" 2>&1)

# Gets information about output file.
	mapfile -t of_remux_info < <(eval ${cmd[1]} -hide_banner -i \""${of_remux}"\" 2>&1)

# Gets HandBrake version.
	mapfile -t hb_version_info < <(eval ${cmd[0]} --version 2>&-)

# Gets the list of HandBrake options.
	mapfile -t hb_opts_info < <(eval ${cmd[0]} --help 2>&-)

# Gets the ffmpeg version.
	mapfile -t ff_version_info < <(eval ${cmd[1]} -version)

# Gets the ffmpeg options.
	mapfile -t ff_opts_info < <(eval ${cmd[1]} -hide_banner -help full)

# Gets the file size of '$if', '$of_remux' and '$of'.
	mapfile -t size_info < <(du -BM "${if}" "${of_remux}" "${of}" 2>&-)

# Gets information about output file from 'mediainfo'.
	mapfile -t mediainfo_info < <(eval ${cmd[5]} -f \""${of}"\" 2>&-)

	declare -A info_elements

	info_elements[if_info]="${#if_info[@]}"
	info_elements[of_info]="${#of_info[@]}"
	info_elements[of_remux_info]="${#of_remux_info[@]}"
	info_elements[hb_version_info]="${#hb_version_info[@]}"
	info_elements[hb_opts_info]="${#hb_opts_info[@]}"
	info_elements[ff_version_info]="${#ff_version_info[@]}"
	info_elements[ff_opts_info]="${#ff_opts_info[@]}"
	info_elements[size_info]="${#size_info[@]}"
	info_elements[mediainfo_info]="${#mediainfo_info[@]}"

# Prints the information gathered from the input file, by ffmpeg.
# Prints the information gathered from the output file, by ffmpeg.
# Prints the information gathered from the remux output file, by ffmpeg.
# Prints the version and options of HandBrake.
# Prints the version and options of ffmpeg.
# Prints file size information.
# Prints the information gathered from the output file, by mediainfo
# (if that command is installed).

	for type in ${info_list_3[@]}; do
		info_f_ref="${type}_f"
		elements="${info_elements[${type}]}"

		for (( i = 0; i < $elements; i++ )); do
			info_ref="${type}[${i}]"

			printf '%s\r\n' "${!info_ref}" >> "${!info_f_ref}"
		done
	done
}

# Creates a function called 'run_or_quit', which will run any command
# stored in the $args array, and quit if the command returns a false
# exit status.
run_or_quit () {
	eval "${args[@]}"

	exit_status="$?"

	if [[ $exit_status -ne 0 ]]; then
		exit $exit_status
	fi
}

# Creates a function called 'check_res', which will check the resolution
# of the input file, to see if it's 1080p, which is the resolution we
# want when using this script.
check_res () {
	regex_video='^ +Stream #.*: Video: .*, ([0-9]+x[0-9]+).*$'
	regex_res='^1920x'

	switch='0'

# Go through the information about the input file, and see if any of the
# lines are video, and if they match the type of video we're looking
# for.
	for (( i = 0; i < ${#if_info[@]}; i++ )); do
# See if the current line is a video track.
		if [[ ${if_info[${i}]} =~ $regex_video ]]; then
			if_res="${BASH_REMATCH[1]}"

			if [[ ! $if_res =~ $regex_res ]]; then
				switch='1'
			fi

			break
		fi
	done

	if [[ $switch -eq 1 ]]; then
		printf '\n%s\n\n' "Wrong resolution (${if_res}) in input file!"
		printf '%s\n\n' "Resolution needs to be 1080p (1920x1080)!"
		exit
	fi
}

# Creates a function called 'is_handbrake', which will check if there
# are any running HandBrake processes, and if so, wait.
is_handbrake () {
	args=(ps -C ${cmd[0]} -o pid,args \| tail -n +2)

	pid_regex='^[[:space:]]*([[:digit:]]+).*'
	comm_regex='^[[:space:]]*[[:digit:]]+[[:space:]]*(.*)'

# Checks if HandBrake is running.
	mapfile -t hb_pids < <(eval "${args[@]}")

# Prints the PID and arguments of the HandBrake commands that are
# running, if any.
	if [[ ${hb_pids[0]} ]]; then
		printf '\n%s\n\n' 'Waiting for this to finish:'
		for (( i = 0; i < ${#hb_pids[@]}; i++ )); do
			pid=$(sed -E "s/${pid_regex}/\1/" <<<"${hb_pids[${i}]}")
			comm=$(sed -E "s/${comm_regex}/\1/" <<<"${hb_pids[${i}]}")

			printf '%s\n' "PID: ${pid}"
			printf '%s\n\n' "COMMAND: ${comm}"
		done
	fi

# Starts the loop that will wait for HandBrake to finish.
	while [[ ${hb_pids[0]} ]]; do
# Sleeps for 5 seconds.
		sleep 5

# Unsets the $hb_pids array.
		unset -v hb_pids

		mapfile -t hb_pids < <(eval "${args[@]}")
	done
}

# Creates a function called 'if_m2ts', which will be called if
# input file is an M2TS, in the directory structure '/BDMV/STREAM/'.
# The function outputs a name, which can be used with the 'break_name'
# function, to get the movie information from IMDb. If the input
# filename doesn't match regex '/BDMV/STREAM/[[:digit:]]{5}.m2ts$',
# return from this function, hence leaving the $if_m2ts variable empty.
if_m2ts () {
	m2ts_regex='/BDMV/STREAM/[[:digit:]]{5}.m2ts$'

	if [[ ! $if =~ $m2ts_regex ]]; then
		return
	fi

	mapfile -d'/' -t count <<<"$if"
	bd_title_field=$(( ${#count[@]} - 3 ))
	bd_title=$(cut -d'/' -f${bd_title_field}- <<<"$if" | cut -d'/' -f1)

	printf '%s' "$bd_title"
}

# Creates a function called 'get_name', which will get the movie title
# and year, based on the input filename.
get_name () {
	year='0000'
	regex='^(.*) ([0-9]{4})$'

# If the input filename is an M2TS, get the movie title and year from
# the surrounding directory structure.
	if_m2ts=$(if_m2ts)

	if [[ ! -z $if_m2ts ]]; then
		bname="$if_m2ts"
	fi

# Breaks up the input filename, and gets its IMDb name.
	bname_tmp=$(break_name "$bname")

# Gets information from IMDb, and removes special characters.
	mapfile -t imdb_tmp < <(fsencode "$(imdb "$bname_tmp")")

# * If IMDb lookup succeeded, use that information.
# * If not, use the information in $bname_tmp instead, but delete
# special characters.
	if [[ ${#imdb_tmp[@]} -eq 2 ]]; then
		title="${imdb_tmp[0]}"
		year="${imdb_tmp[1]}"
	else
		bname_tmp_fs=$(fsencode "$bname_tmp")

		if [[ $bname_tmp_fs =~ $regex ]]; then
			title=$(sed -E "s/${regex}/\1/" <<<"$bname_tmp_fs")
			year=$(sed -E "s/${regex}/\2/" <<<"$bname_tmp_fs")
		else
			title="$bname_tmp_fs"
		fi
	fi

	title=$(tr ' ' '.' <<<"$title")

	printf '%s\n' "$title"
	printf '%s\n' "$year"
}

# Gets information about input file.
mapfile -t if_info < <(eval ${cmd[1]} -hide_banner -i \""${if}"\" 2>&1)

# Gets the movie title and year.
mapfile -t get_name_tmp < <(get_name)
title="${get_name_tmp[0]}"
year="${get_name_tmp[1]}"

# Creates a directory structure in the current user's home directory:
# "${title}.${year}.${rls_type}/Info"
of_bname="${title}.${year}.${rls_type}"
of_dir="${of_dir}/${of_bname}"
info_dir="${of_dir}/Info"
mkdir -p "$info_dir"

# Creates the output filename, as well as the remux output filename.
of="${of_dir}/${of_bname}.mkv"
of_tmp="${of_dir}/${of_bname}.TMP-${session}.mkv"
of_remux="${of_dir}/${title}.${year}.REMUX.mkv"

# Creates a filename which will contain the commands run by this script.
# Also creates a filename that will store the output from HandBrake.
# If the filename already exists, delete that file, and then create
# a new one.
command_f="${of_dir}/Info/${title}.${year}_commands.txt"
hb_log_f="${of_dir}/Info/${title}.${year}_HandBrake_log.txt"

for txt_f in "$command_f" "$hb_log_f"; do
	if [[ -f $txt_f ]]; then
		rm "$txt_f"
	fi
	touch "$txt_f"
done

if [[ $exist -ne 1 ]]; then
# If output filename already exists, add a random number to the end of
# the filename.
	if [[ -f $of ]]; then
		of="${of_dir}/${of_bname}-${session}.mkv"
	elif [[ -f $of_remux ]]; then
		of_remux="${of_dir}/${title}.${year}.REMUX-${session}.mkv"
	fi
fi

# * Checks the resolution of the input file.
# * Checks if HandBrake is already running, and if so, wait.
# * Extracts the core DTS track.
# * Remuxes input file, without all its audio tracks, with the core
# DTS track.
# * Encodes the remux with HandBrake.
# * Merges the finished encode with the subtitles from the source file.
# * Creates info txt files for input file, output file and remux
# output file.
check_res
is_handbrake
dts_extract_remux
hb_encode

if [[ $hb_subs -ne 1 ]]; then
	sub_mux
fi

info_txt
