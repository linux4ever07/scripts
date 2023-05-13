#!/bin/bash

# Usage: bluray_remux2hevc.sh [mkv|m2ts] -out [directory] [...]

# This script will:
# * Parse the input filename (a 1080p Blu-Ray (remux or full)), get
# movie info from IMDb, incl. name and year.
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

# First argument to this script should be a file, typically an MKV or
# M2TS.

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
	Pass the subs directly to HandBrake instead of mkvmerge.

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

# If first argument is empty, or is not a real file, then print
# syntax and quit.
if [[ ! -f $1 ]]; then
	usage
fi

# Gets full path of input file.
if=$(readlink -f "$1")
bname=$(basename "$if")

# Generates a random number, which can be used for these filenames:
# output, output remux, input info txt, output info txt, output remux
# info txt.
session="${RANDOM}-${RANDOM}"

# Creates a variable that will work as a switch. If this variable is set
# to '1', it will skip running the 'dts_extract_remux' and 'remux_mkv'
# functions. This is handy if that file has already been created in
# a previous session of this script.
exist=0

# Creates a variable that will work as a switch. If this variable is set
# to '1', it will pass the subtitles from the input file to HandBrake.
# This is to prevent the subtitles from going out of sync with the audio
# and video, when dealing with input files that have been merged from
# multiple Blu-Ray discs.
hb_subs=0

# Sets the default language to English. This language code is what
# the script till look for when extracting the core DTS track.
lang='eng'

# Creates a variable that will decide what kind of x265 tuning to use,
# if any.
declare tune

# Creates some global regexes.
regex_blank='^[[:blank:]]*(.*)[[:blank:]]*$'
regex_zero='^0+([0-9]+)$'

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

# The loop below handles the arguments to the script.
shift

while [[ $# -gt 0 ]]; do
	case "$1" in
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

			regex_lang='^[[:alpha:]]{3}$'

			if [[ ! $1 =~ $regex_lang ]]; then
				usage
			else
				lang="${1,,}"
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

			if [[ -n $tune ]]; then
				usage
			fi

			tune='anime'
		;;
		'-grain')
			shift

			if [[ -n $tune ]]; then
				usage
			fi

			tune='grain'
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
cmd=('HandBrakeCLI' 'ffmpeg' 'mkvmerge' 'curl' 'flac')

# This creates a function called 'check_cmd', which will check if the
# necessary commands are installed. If any of the commands are missing
# print them and quit.
check_cmd () {
	declare -a missing_pkg
	declare -A cmd_pkg

# Saves the package names of the commands that are needed by the script.
	cmd_pkg["${cmd[0]}"]='HandBrake'
	cmd_pkg["${cmd[1]}"]='ffmpeg'
	cmd_pkg["${cmd[2]}"]='mkvtoolnix'
	cmd_pkg["${cmd[3]}"]='curl'
	cmd_pkg["${cmd[4]}"]='flac'

	for cmd_tmp in "${cmd[@]}"; do
		command -v "$cmd_tmp" 1>&-

		if [[ $? -ne 0 ]]; then
			missing_pkg+=("$cmd_tmp")
		fi
	done

	if [[ ${#missing_pkg[@]} -gt 0 ]]; then
		printf '\n%s\n\n' 'You need to install the following through your package manager:'

		for cmd_tmp in "${missing_pkg[@]}"; do
			printf '%s\n' "${cmd_pkg[${cmd_tmp}]}"
		done

		printf '\n'

		exit
	fi
}

# This creates a function called 'fsencode', which will delete special
# characters that are not allowed in filenames on certain filesystems.
# The characters in the regex are allowed. All others are deleted. Based
# on the "POSIX fully portable filenames" entry:
# https://en.wikipedia.org/wiki/Filename#Comparison_of_filename_limitations
fsencode () {
	sed -E 's/[^ A-Za-z0-9._-]//g' <<<"$1"
}

# This creates a function called 'uriencode', which will translate
# the special characters in any string to be URL friendly. This will be
# used in the 'imdb' function.
uriencode () {
	url_string="$@"

	curl -Gso /dev/null -w %{url_effective} --data-urlencode "$url_string" 'http://localhost' | sed -E 's/^.{18}(.*)/\1/'
}

# This creates a function called 'break_name', which will break up
# the input filename, and parse it, to extract the movie name, and year.
break_name () {
# Sets $bname to the first argument passed to this function.
	bname=$(sed -E 's/[[:blank:]]+/ /g' <<<"$1")

	declare -a name

	types=('dots' 'hyphens' 'underscores' 'spaces')

	regex='^(.*)([[:punct:]]|[[:blank:]]){1,}([0-9]{4})([[:punct:]]|[[:blank:]]){1,}(.*)$'

# If $temp can't be parsed, set it to the input filename instead,
# although limit the string by 64 characters, and remove possible
# trailing whitespace from the string.
	if [[ $bname =~ $regex ]]; then
		temp="${BASH_REMATCH[1]}"
		year="(${BASH_REMATCH[3]})"
	else
		temp=$(sed -E "s/${regex_blank}/\1/" <<<"${bname:0:64}")
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
	bname_elements[dots]="${#bname_dots[@]}"
	bname_elements[hyphens]="${#bname_hyphens[@]}"
	bname_elements[underscores]="${#bname_underscores[@]}"
	bname_elements[spaces]="${#bname_spaces[@]}"

# If there are more dots in $bname than hyphens, underscores or spaces,
# that means $bname is separated by dots. Otherwise, it's separated by
# hyphens, underscores or spaces. In either case, loop through the word
# list in either array, and break the name up in separate words.
	elements=0

# This for loop is to figure out if $bname is separated by dots,
# hyphens, underscores or spaces.
	for type in "${types[@]}"; do
		number_ref="bname_elements[${type}]"

		if [[ ${!number_ref} -gt $elements ]]; then
			elements="${!number_ref}"
			temp_type="$type"
		fi
	done

# This for loop is to go through the word list.
	for (( i = 0; i < elements; i++ )); do
# Creates a reference, pointing to the $i element of the
# 'bname_$temp_type' array.
		array_ref="bname_${temp_type}[${i}]"

		if [[ -n ${!array_ref} ]]; then
			name+=("${!array_ref}")
		fi
	done

	if [[ -n $year ]]; then
		name+=("$year")
	fi

# Prints the complete parsed name.
	name_string="${name[@]}"
	printf '%s' "$name_string"
}

# This creates a function called 'imdb', which will look up the movie
# name on IMDb, based on the file name of the input file.
# https://www.imdb.com/search/title/
# https://www.imdb.com/interfaces/
imdb () {
	if [[ $# -eq 0 ]]; then
		return 1
	fi

	mapfile -d' ' -t term < <(sed -E 's/[[:blank:]]+/ /g' <<<"$@")
	term[-1]="${term[-1]%$'\n'}"

	y_regex='^\(([0-9]{4})\)$'

	id_regex='^.*\/title\/(tt[0-9]+).*$'
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
	actor_regex1='\,\"actor\":\['
	actor_regex2='\"@type\":\"Person\",\"url\":\".*\"\,\"name\":\"(.*)\"'
	director_regex1='\]\,\"director\":\['
	director_regex2='\"@type\":\"Person\",\"url\":\".*\"\,\"name\":\"(.*)\"'
	runtime_regex1='\,\"runtime\":'
	runtime_regex2='\"seconds\":(.*)\,\"displayableProperty\":'

	agent='Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/109.0.0.0 Safari/537.36'

# This function gets a URL using cURL.
	get_page () {
		curl --location --user-agent "$agent" --retry 10 --retry-delay 10 --connect-timeout 10 --silent "$1" 2>&-
	}

# This function runs the JSON regexes and decides which JSON type is a
# list and which isn't.
	get_list () {
		declare string
		declare -a list
		declare -A lists

		lists=(['genre']=1 ['actor']=1 ['director']=1)

		regex_list='^,$'

		z=$(( z + 1 ))

# If current JSON type is not a list, match the regex and return from
# this function.
		if [[ -z ${lists[${json_type}]} ]]; then
			if [[ ${tmp_array[${z}]} =~ ${!json_regex2_ref} ]]; then
				eval "${json_type}"=\""${BASH_REMATCH[1]}"\"
			fi

			return
		fi

# This loop parses JSON lists.
		while [[ ${tmp_array[${z}]} =~ ${!json_regex2_ref} ]]; do
			list+=("${BASH_REMATCH[1]}")

			z=$(( z + 1 ))

			if [[ ${tmp_array[${z}]} =~ $regex_list ]]; then
				z=$(( z + 1 ))
			else
				z=$(( z - 1 ))
				break
			fi
		done

		string=$(printf '%s, ' "${list[@]}")
		string="${string%, }"

		eval "${json_type}"=\""${string}"\"
	}

	if [[ ${term[-1]} =~ $y_regex ]]; then
		y="${BASH_REMATCH[1]}"
		unset -v term[-1]
	fi

	t=$(uriencode "${term[@]}")

# Sets the type of IMDb search results to include.

# All currently available types:
# feature,tv_movie,tv_series,tv_episode,tv_special,tv_miniseries,
# documentary,video_game,short,video,tv_short,podcast_series,
# podcast_episode,music_video
	type='feature,tv_movie,tv_special,documentary,video'

# If the $y variable is empty, that means the year is unknown, hence we
# will need to use slightly different URLs, when searching for the
# movie.
	if [[ -z $y ]]; then
		url_tmp="https://www.imdb.com/search/title/?title=${t}&title_type=${type}&view=simple"
	else
		url_tmp="https://www.imdb.com/search/title/?title=${t}&title_type=${type}&release_date=${y},${y}&view=simple"
	fi

	mapfile -t id_array < <(get_page "$url_tmp" | sed -nE "s/${id_regex}/\1/p")
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
	mapfile -t tmp_array < <(get_page "$url" | tr '{}' '\n' | grep -Ev -e '.{500}' -e '^[[:blank:]]*$')

	declare -A json_types

	json_types=(['title']=1 ['year']=1 ['plot']=1 ['rating']=1 ['genre']=1 ['actor']=1 ['director']=1 ['runtime']=1)

	for (( z = 0; z < ${#tmp_array[@]}; z++ )); do
		if [[ ${#json_types[@]} -eq 0 ]]; then
			break
		fi

		for json_type in "${!json_types[@]}"; do
			json_regex1_ref="${json_type}_regex1"
			json_regex2_ref="${json_type}_regex2"

			if [[ ${tmp_array[${z}]} =~ ${!json_regex1_ref} ]]; then
				get_list

				unset -v json_types["${json_type}"]
				break
			fi
		done
	done

	printf '%s\n' "$title"
	printf '%s\n' "$year"
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
	regex_audio="^ +Stream #(0:[0-9]+)(\(${lang}\)){0,1}: Audio: .*$"
	regex_51=', 5.1\(.*\),'

	regex_stream='^ +Stream #'
	regex_kbps=', ([0-9]+) kb\/s'
	regex_bps='^ +BPS.*: ([0-9]+)$'
	regex_last3='^[0-9]+([0-9]{3})$'

	high_kbps='1536'
	low_kbps='768'
	high_bps='1537000'
	low_bps='769000'
	bps_limit=$(( (high_bps - low_bps) / 2 ))
	use_kbps="${high_kbps}k"

	declare -A type elements audio_tracks
	type[dts_hdma]='dts \(DTS-HD MA\)'
	type[truehd]='truehd'
	type[pcm]='pcm_bluray'
	type[flac]='flac'
	type[dts]='dts \(DTS(-ES){0,1}\)'
	type[ac3]='ac3'
	elements[dts_hdma]=0
	elements[truehd]=0
	elements[pcm]=0
	elements[flac]=0
	elements[dts]=0
	elements[ac3]=0

	audio_types=('dts_hdma' 'truehd' 'pcm' 'flac' 'dts' 'ac3')

	if_info_tmp=("${if_info[@]}")

# Creates a function called 'parse_ffmpeg', which will parse the output
# from ffmpeg, get all the streams and bitrates.
	parse_ffmpeg () {
		declare n

		for (( i = 0; i < ${#if_info_tmp[@]}; i++ )); do
			line="${if_info_tmp[${i}]}"

# If line is a stream...
			if [[ $line =~ $regex_stream ]]; then
				if [[ -z $n ]]; then
					n=0
				else
					n=$(( n + 1 ))
				fi

				streams["${n}"]="$line"

# If stream line contains bitrate, use that.
				if [[ $line =~ $regex_kbps ]]; then
					bps=$(( ${BASH_REMATCH[1]} * 1000 ))
					bitrates["${n}"]="$bps"
				fi
			fi

# If line is a bitrate...
			if [[ $line =~ $regex_bps ]]; then
				bps="${BASH_REMATCH[1]}"

# If bitrate has already been set, skip this line.
				if [[ -n ${bitrates[${n}]} ]]; then
					continue
				fi

# If input bitrate consists of at least 4 digits, get the last 3 digits.
				if [[ $bps =~ $regex_last3 ]]; then
					bps_last="${BASH_REMATCH[1]}"

					if [[ $bps_last =~ $regex_zero ]]; then
						bps_last="${BASH_REMATCH[1]}"
					fi

					bps=$(( bps - bps_last ))

# If the last 3 digits are equal to (or higher than) 500, then round up
# that number, otherwise round it down.
					if [[ $bps_last -ge 500 ]]; then
						bps=$(( bps + 1000 ))
					fi
				fi

				bitrates["${n}"]="$bps"
			fi
		done
	}

# Creates a function called 'get_bitrate', which will decide what DTS
# bitrate to use for the output file.
	get_bitrate () {
		declare bps_if

# If $audio_format is 'flac', we will decode the FLAC audio track in
# order to get the correct (uncompressed) bitrate, which will later be
# used to calculate the output bitrate.
		if [[ $audio_format == 'flac' ]]; then
			flac_tmp="${of_dir}/FLAC.TMP-${session}.flac"
			wav_tmp="${of_dir}/FLAC.TMP-${session}.wav"

# Extracts the FLAC track from $if, and decodes it to WAV.
			args=("${cmd[1]}" -i \""${if}"\" -map "${map}" -c:a copy \""${flac_tmp}"\")
			run_or_quit
			args=("${cmd[4]}" -d \""${flac_tmp}"\")
			run_or_quit
			args=(rm \""${flac_tmp}"\")
			run_or_quit

# Gets information about the WAV file.
			mapfile -t if_info_tmp < <(eval "${cmd[1]}" -hide_banner -i \""${wav_tmp}"\" 2>&1)
			args=(rm \""${wav_tmp}"\")
			run_or_quit

			unset -v streams bitrates
			declare -a streams bitrates
			parse_ffmpeg

			for (( i = 0; i < ${#streams[@]}; i++ )); do
# See if the current line is an audio track. If so, save the bitrate.
				if [[ ${streams[${i}]} =~ $regex_audio ]]; then
					bps_if="${bitrates[${i}]}"
					break
				fi
			done
		else
			for (( i = 0; i < ${#streams[@]}; i++ )); do
# See if the current line matches the chosen audio track. If so, save
# the bitrate.
				if [[ ${streams[${i}]} == "${!audio_track_ref}" ]]; then
					bps_if="${bitrates[${i}]}"
					break
				fi
			done
		fi

# If audio track bitrate could not be found, return from this function.
		if [[ -z $bps_if ]]; then
			return
		fi

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

	declare -a streams bitrates
	parse_ffmpeg

# Go through the information about the input file, and see if any of the
# lines are audio, and if they match the types of audio we're looking
# for.
	for (( i = 0; i < ${#streams[@]}; i++ )); do
# See if the current line is an audio track, and the same language as
# $lang.
		if [[ ${streams[${i}]} =~ $regex_audio ]]; then
			for tmp_type in "${audio_types[@]}"; do
				n="elements[${tmp_type}]"

				if [[ ${streams[${i}]} =~ ${type[${tmp_type}]} ]]; then
					audio_tracks["${tmp_type},${!n}"]="${streams[${i}]}"
					elements["${tmp_type}"]=$(( ${!n} + 1 ))
				fi
			done
		fi
	done

	switch=0

# Go through the different types of audio and see if we have a matching
# 5.1 track in one of those formats.
	for tmp_type in "${audio_types[@]}"; do
		for (( i = 0; i < ${elements[${tmp_type}]}; i++ )); do
			hash_ref="audio_tracks[${tmp_type},${i}]"

			if [[ ${!hash_ref} =~ $regex_51 ]]; then
				audio_track_ref="$hash_ref"
				audio_format="$tmp_type"
				switch=1
				break
			fi
		done

		if [[ $switch -eq 1 ]]; then
			break
		fi
	done

# Pick the first audio track in the list, in the preferred available
# format, if $audio_track_ref is still empty.
	if [[ -z $audio_track_ref ]]; then
		for tmp_type in "${audio_types[@]}"; do
			if [[ ${elements[${tmp_type}]} -gt 0 ]]; then
				audio_track_ref="audio_tracks[${tmp_type},0]"
				audio_format="$tmp_type"
				break
			fi
		done
	fi

	if [[ -z $audio_track_ref ]]; then
		cat <<NO_MATCH

${if}

There are no suitable audio tracks in input file. It either has no audio
tracks at all, or they're in the wrong format or have the wrong language
code. A possible fix is checking the language of the input file, and
specifying the correct language code as argument to the script.
		
Listing all streams found in input file:

NO_MATCH

		printf '%s\n' "${streams[@]}"
		printf '\n'

		exit
	fi

# Gets the ffmpeg map code of the audio track.
	map=$(sed -E "s/${regex_audio}/\1/" <<<"${!audio_track_ref}")

# Creates first part of ffmpeg command.
	args1=("${cmd[1]}" -i \""${if}"\" -metadata title=\"\" -map 0:v -map "${map}" -map 0:s?)

# Creates ffmpeg command.
	case "$audio_format" in
		'dts_hdma')
			args=("${args1[@]}" -bsf:a dca_core -c:v copy -c:a copy -c:s copy \""${of_remux}"\")
		;;
		'truehd')
			args=("${args1[@]}" -strict -2 -c:v copy -c:a dts -c:s copy -ab "${use_kbps}" \""${of_remux}"\")
		;;
		'pcm')
			get_bitrate
			args=("${args1[@]}" -strict -2 -c:v copy -c:a dts -c:s copy -ab "${use_kbps}" \""${of_remux}"\")
		;;
		'flac')
			get_bitrate
			args=("${args1[@]}" -strict -2 -c:v copy -c:a dts -c:s copy -ab "${use_kbps}" \""${of_remux}"\")
		;;
		'dts')
			args=("${args1[@]}" -c:v copy -c:a copy -c:s copy \""${of_remux}"\")
		;;
		'ac3')
			get_bitrate
			args=("${args1[@]}" -strict -2 -c:v copy -c:a dts -c:s copy -ab "${use_kbps}" \""${of_remux}"\")
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
	args1=("${cmd[0]}" --format "${format}" --markers --encoder "${v_encoder}" --encoder-preset "${preset}")

	if [[ $hb_subs -eq 1 ]]; then
		args2=(--vb "${v_bitrate}" --two-pass --vfr --aencoder "${a_encoder}" --all-subtitles -i \""${of_remux}"\" -o \""${of}"\")
	else
		args2=(--vb "${v_bitrate}" --two-pass --vfr --aencoder "${a_encoder}" -i \""${of_remux}"\" -o \""${of}"\")
	fi

	args3=(2\> \>\(tee \""${hb_log_f}"\"\))

	anime_tune='--encoder-tune animation'
	grain_tune='--encoder-tune grain'

# Creates the HandBrake command, which will be used to encode the input
# file to a HEVC output file. Depending on whether $tune is set or not,
# we get a different HandBrake command.
	case "$tune" in
		'anime')
			args=("${args1[@]}" "${anime_tune}" "${args2[@]}" "${args3[@]}")
		;;
		'grain')
			args=("${args1[@]}" "${grain_tune}" "${args2[@]}" "${args3[@]}")
		;;
		*)
			args=("${args1[@]}" "${args2[@]}" "${args3[@]}")
		;;
	esac

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

	if [[ ${#if_subs[@]} -eq 0 ]]; then
		return
	fi

	args=("${cmd[2]}" --title \"\" -o \""${of_tmp}"\" \""${of}"\" --no-video --no-audio --no-chapters \""${of_remux}"\")

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

	cmd[5]=$(basename "$(command -v "mediainfo")")

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

	if [[ -n ${cmd[5]} ]]; then
		info_list_1=('if_info' 'of_info' 'of_remux_info' 'mediainfo_info')
	else
		info_list_1=('if_info' 'of_info' 'of_remux_info')
	fi

	info_list_2=('hb_version_info' 'hb_opts_info' 'ff_version_info' 'ff_opts_info' 'size_info')
	info_list_3=("${info_list_1[@]}" "${info_list_2[@]}")

# If the info txt filenames (in list 1) already exist, add a random
# number to the end of the filename.
	for txt_f in "${info_list_1[@]}"; do
		txt_ref="${txt_f}_f"

		if [[ -f ${!txt_ref} ]]; then
			txt_tmp="${!txt_ref%.txt}"

			eval "${txt_f}"_f="${txt_tmp}-${session}.txt"
		fi
	done

# Gets information about output file.
# Gets information about remux output file.
# Gets the HandBrake version.
# Gets the HandBrake options.
# Gets the ffmpeg version.
# Gets the ffmpeg options.
# Gets the file size of '$if', '$of_remux' and '$of'.
# Gets information about output file from 'mediainfo'.
	mapfile -t of_info < <(eval "${cmd[1]}" -hide_banner -i \""${of}"\" 2>&1)
	mapfile -t of_remux_info < <(eval "${cmd[1]}" -hide_banner -i \""${of_remux}"\" 2>&1)
	mapfile -t hb_version_info < <(eval "${cmd[0]}" --version 2>&-)
	mapfile -t hb_opts_info < <(eval "${cmd[0]}" --help 2>&-)
	mapfile -t ff_version_info < <(eval "${cmd[1]}" -version)
	mapfile -t ff_opts_info < <(eval "${cmd[1]}" -hide_banner -help full)
	mapfile -t size_info < <(du -BM "${if}" "${of_remux}" "${of}" 2>&-)
	mapfile -t mediainfo_info < <(eval "${cmd[5]}" -f \""${of}"\" 2>&-)

# Prints the information gathered from the input file, by ffmpeg.
# Prints the information gathered from the output file, by ffmpeg.
# Prints the information gathered from the remux output file, by ffmpeg.
# Prints the version and options of HandBrake.
# Prints the version and options of ffmpeg.
# Prints file size information.
# Prints the information gathered from the output file, by mediainfo
# (if that command is installed).
	for type in "${info_list_3[@]}"; do
		info_f_ref="${type}_f"
		info_ref="${type}[@]"

		printf '%s\r\n' "${!info_ref}" > "${!info_f_ref}"
	done
}

# Creates a function called 'run_or_quit', which will run any command
# stored in the $args array, and quit if the command returns a false
# exit status.
run_or_quit () {
	eval "${args[@]}" || exit "$?"
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
	args=(ps -C "${cmd[0]}" -o pid,args \| tail -n +2)

	regex_pid_comm='^[[:blank:]]*([0-9]+)[[:blank:]]*(.*)$'

# Checks if HandBrake is running.
	mapfile -t hb_pids < <(eval "${args[@]}")

# Prints the PID and arguments of the HandBrake commands that are
# running, if any.
	if [[ ${#hb_pids[@]} -gt 0 ]]; then
		printf '\n%s\n\n' 'Waiting for this to finish:'

		for (( i = 0; i < ${#hb_pids[@]}; i++ )); do
			if [[ ${hb_pids[${i}]} =~ $regex_pid_comm ]]; then
				pid="${BASH_REMATCH[1]}"
				comm="${BASH_REMATCH[2]}"

				printf '%s: %s\n' 'PID' "$pid"
				printf '%s: %s\n\n' 'COMMAND' "$comm"
			fi
		done
	fi

# Starts the loop that will wait for HandBrake to finish.
	while [[ ${#hb_pids[@]} -gt 0 ]]; do
# Sleeps for 5 seconds.
		sleep 5

# Checks again if HandBrake is running.
		mapfile -t hb_pids < <(eval "${args[@]}")
	done
}

# Creates a function called 'if_m2ts', which will be called if
# input file is an M2TS, in the directory structure '/BDMV/STREAM/'.
# The function outputs a name, which can be used with the 'break_name'
# function, to get the movie information from IMDb. If the input
# filename doesn't match the regex in $regex_m2ts, return from this
# function, hence leaving the $if_m2ts variable empty.
if_m2ts () {
	regex_m2ts='\/BDMV\/STREAM\/[0-9]+\.m2ts$'

	if [[ ! $if =~ $regex_m2ts ]]; then
		return
	fi

	mapfile -d'/' -t path_parts <<<"$if"
	field=$(( ${#path_parts[@]} - 4 ))
	bd_title="${path_parts[${field}]}"

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

	if [[ -n $if_m2ts ]]; then
		bname="$if_m2ts"
	fi

# Breaks up the input filename, and gets its IMDb name.
	bname_tmp=$(break_name "$bname")

# Gets information from IMDb, and removes special characters.
	mapfile -t imdb_tmp < <(fsencode "$(imdb "$bname_tmp")")

# If IMDb lookup succeeded, use that information.
# If not, use the information in $bname_tmp instead, but delete special
# characters.
	if [[ -n ${imdb_tmp[0]} ]]; then
		title="${imdb_tmp[0]}"
		year="${imdb_tmp[1]}"
	else
		bname_tmp_fs=$(fsencode "$bname_tmp")

		if [[ $bname_tmp_fs =~ $regex ]]; then
			title="${BASH_REMATCH[1]}"
			year="${BASH_REMATCH[2]}"
		else
			title="$bname_tmp_fs"
		fi
	fi

	title=$(tr ' ' '.' <<<"$title")

	printf '%s\n' "$title"
	printf '%s\n' "$year"
}

# Creates a function called 'is_torrent', which checks if the filename
# ends with '.part', or if there's a filename in the same directory that
# ends with '.part'. If there is, wait until the filename changes, and
# '.part' is removed from the filename. This function recognizes if
# input file is an unfinished download, and waits for the file to fully
# download before processing it.
is_torrent () {
	regex_part='\.part$'

	if [[ $if =~ $regex_part ]]; then
		if_tmp="$if"
	else
		if_tmp="${if}.part"
	fi

	if [[ -f $if_tmp ]]; then
		printf '\n%s\n' 'Waiting for this download to finish:'
		printf '%s\n\n' "$if_tmp"

		while [[ -f $if_tmp ]]; do
			sleep 5
		done

		if="${if%.part}"

		md5=$(md5sum -b "$if")
		md5_f="${HOME}/${bname}_MD5-${session}.txt"

		printf '%s\r\n' "$md5" | tee "$md5_f"
	fi
}

check_cmd

is_torrent

# Gets information about input file.
mapfile -t if_info < <(eval "${cmd[1]}" -hide_banner -i \""${if}"\" 2>&1)

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
