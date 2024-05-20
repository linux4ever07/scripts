#!/bin/bash

# Usage: bluray_remux2hevc.sh [mkv|m2ts] -out [directory] [...]

# This script will:
# * Parse the input file name (a 1080p Blu-Ray (remux or full)), get
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

# Creates a function, called 'usage', which prints the syntax,
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

declare -A if of

# Gets full path of input file.
if[fn]=$(readlink -f "$1")
if[bn]=$(basename "${if[fn]}")

# Declares some global variables:
# * 'title' is the name of the movie.
# * 'year' is the year of the movie.
# * 'tune' will decide what kind of x265 tuning to use, if any.
# * 'lang' is the language to be used for the audio track.
# * 'session' is a random number to be used in some file names.
# * 'exist' is a switch that tells the script to skip creating the
# output remux file.
# * 'hb_subs' is a switch that tells the script to pass the subs
# directly to HandBrake.
declare title year tune lang session exist hb_subs txt_fn
declare format v_encoder preset v_bitrate a_encoder rls_type
declare -a cmd maps langs bitrates if_info
declare -A regex streams

# Creates some global regexes.
regex[blank]='^[[:blank:]]*(.*)[[:blank:]]*$'
regex[zero]='^0+([0-9]+)$'
regex[last3]='^[0-9]+([0-9]{3})$'

regex[lang1]='^[[:alpha:]]{3}$'

# Sets the default audio language to English.
lang='eng'

# Generates a random number, which can be used for these file names:
# output, output remux, input info txt, output info txt, output remux
# info txt.
session="${RANDOM}-${RANDOM}"

# Creates a variable that will work as a switch. If this variable is set
# to '1', it will skip running the 'dts_extract_remux' function. This is
# handy if that file has already been created in a previous session of
# this script.
exist=0

# Creates a variable that will work as a switch. If this variable is set
# to '1', it will pass the subtitles from the input file to HandBrake.
# This is to prevent the subtitles from going out of sync with the audio
# and video, when dealing with input files that have been merged from
# multiple Blu-Ray discs.
hb_subs=0

# The loop below handles the arguments to the script.
shift

while [[ $# -gt 0 ]]; do
	case "$1" in
		'-out')
			shift

			if [[ ! -d $1 ]]; then
				usage
			else
				of[dn]=$(readlink -f "$1")
			fi

			shift
		;;
		'-lang')
			shift

			if [[ ! $1 =~ ${regex[lang1]} ]]; then
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

if [[ -z ${of[dn]} ]]; then
	usage
fi

# Creates some function-specific regexes.
regex[lang2]="^(${lang}|und)$"

regex[year]='^([[:punct:]]|[[:blank:]]){0,1}([0-9]{4})([[:punct:]]|[[:blank:]]){0,1}$'

regex[stream1]='^ +Stream #(0:[0-9]+).*$'
regex[stream2]='^ +Stream #0:[0-9]+(\([[:alpha:]]+\)){0,1}: ([[:alpha:]]+): (.*)$'

regex[kbps]='^([0-9]+) kb\/s'
regex[bps]='^ +BPS.*: ([0-9]+)$'

regex[surround]='^([2-9])\.1(\(.*\)){0,1}$'

regex[res]='^([0-9]+)x[0-9]+$'

regex[pid_comm]='^[[:blank:]]*([0-9]+)[[:blank:]]*(.*)$'

regex[m2ts]='\/BDMV\/STREAM\/[0-9]+\.m2ts$'

regex[part]='\.part$'

# Creates some variables that will be used to create a full HandBrake
# command, with args.
format='av_mkv'
v_encoder='x265_10bit'
preset='slow'
v_bitrate=5000
a_encoder='copy:dts'

# Creates a variable which contains the last part of the output
# file name.
rls_type='1080p.BluRay.x265.DTS'

# Creates an array of the list of commands needed by this script.
cmd=('HandBrakeCLI' 'ffmpeg' 'mkvmerge' 'curl' 'flac')

# Creates a function, called 'check_cmd', which will check if the
# necessary commands are installed. If any of the commands are missing,
# print them and quit.
check_cmd () {
	declare cmd_tmp
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

# Creates a function, called 'fsencode', which will delete special
# characters that are not allowed in file names on certain filesystems.
# The characters in the regex are allowed. All others are deleted. Based
# on the 'POSIX fully portable file names' entry:
# https://en.wikipedia.org/wiki/Filename#Comparison_of_filename_limitations
fsencode () {
	sed -E 's/[^ A-Za-z0-9._-]//g' <<<"$1"
}

# Creates a function, called 'uriencode', which will translate the
# special characters in any string to be URL friendly. This will be
# used in the 'imdb' function.
uriencode () {
	declare url_string

	url_string="$@"

	curl -Gso /dev/null -w %{url_effective} --data-urlencode "$url_string" 'http://localhost' | sed -E 's/^.{18}(.*)$/\1/'
}

# Creates a function, called 'break_name', which will break up the
# input file name, and parse it, to extract the movie title, and year.
break_name () {
	declare bname array_ref number_ref elements type type_tmp
	declare -a types
	declare -a bname_dots bname_hyphens bname_underscores bname_spaces
	declare -A bname_elements

	bname=$(sed -E 's/ +/ /g' <<<"$1")

	types=('dots' 'hyphens' 'underscores' 'spaces')

# Breaks the name up in a list of words, and stores those words in
# arrays, depending on whether the file name is separated by dots,
# hyphens, underscores or spaces.
	mapfile -d'.' -t bname_dots <<<"$bname"
	mapfile -d'-' -t bname_hyphens <<<"$bname"
	mapfile -d'_' -t bname_underscores <<<"$bname"
	mapfile -d' ' -t bname_spaces <<<"$bname"

# Gets rid of the newline at the end of the last element of each array.
	bname_dots[-1]="${bname_dots[-1]%$'\n'}"
	bname_hyphens[-1]="${bname_hyphens[-1]%$'\n'}"
	bname_underscores[-1]="${bname_underscores[-1]%$'\n'}"
	bname_spaces[-1]="${bname_spaces[-1]%$'\n'}"

# Stores the total element numbers in the 'bname_elements' hash.
# This will be used to figure out the correct word separator.
	bname_elements[dots]="${#bname_dots[@]}"
	bname_elements[hyphens]="${#bname_hyphens[@]}"
	bname_elements[underscores]="${#bname_underscores[@]}"
	bname_elements[spaces]="${#bname_spaces[@]}"

	elements=0

# This for loop figures out if the name is separated by dots, hyphens,
# underscores or spaces.
	for type in "${types[@]}"; do
		number_ref="bname_elements[${type}]"

		if [[ ${!number_ref} -gt $elements ]]; then
			elements="${!number_ref}"
			type_tmp="$type"
		fi
	done

	declare title_tmp year_tmp

	year_tmp='0000'

# This for loop goes through the word list from right to left, until it
# finds a year. If the year is found, it's saved in a variable, and the
# elements variable is modified so the next for loop will not go beyond
# the element that contains the year, when saving the words that
# comprise the title.
	for (( i = elements; i > 0; i-- )); do
		array_ref="bname_${type_tmp}[${i}]"

		if [[ -z ${!array_ref} ]]; then
			continue
		fi

# If this element matches the year regex, stop going through the
# array elements.
		if [[ ${!array_ref} =~ ${regex[year]} ]]; then
			year_tmp="${BASH_REMATCH[2]}"

			elements="$i"

			break
		fi
	done

# This for loop goes through the word list that comprises the title.
	for (( i = 0; i < elements; i++ )); do
		array_ref="bname_${type_tmp}[${i}]"

		if [[ -z ${!array_ref} ]]; then
			continue
		fi

		title_tmp+="${!array_ref} "
	done

	title_tmp="${title_tmp% }"

# Prints the complete parsed name.
	printf '%s\n' "$title_tmp"
	printf '%s\n' "$year_tmp"
}

# Creates a function, called 'imdb', which will look up the movie name
# on IMDb, based on the file name of the input file.
# https://www.imdb.com/search/title/ https://www.imdb.com/interfaces/
imdb () {
	if [[ $# -eq 0 ]]; then
		return 1
	fi

	declare agent y t type url_tmp url id json_type
	declare -a term tmp_array
	declare -A json_types imdb_info

	mapfile -t term < <(sed -E 's/[[:blank:]]+/\n/g' <<<"$@")

	regex[y]='^\(([0-9]{4})\)$'
	regex[id]='(title\/tt[0-9]+)'
	regex[list]='^,$'

	regex[title1]='\,\"originalTitleText\":'
	regex[title2]='\"text\":\"(.*)\"\,\"__typename\":\"TitleText\"'
	regex[year1]='\,\"releaseYear\":'
	regex[year2]='\"year\":([0-9]{4})\,\"endYear\":.*\,\"__typename\":\"YearRange\"'
	regex[plot1]='\"plotText\":'
	regex[plot2]='\"plainText\":\"(.*)\"\,\"__typename\":\"Markdown\"'
	regex[rating1]='\,\"ratingsSummary\":'
	regex[rating2]='\"aggregateRating\":(.*)\,\"voteCount\":.*\,\"__typename\":\"RatingsSummary\"'
	regex[genre1]='\"genres\":\['
	regex[genre2]='\"text\":\"(.*)\"\,\"id\":\".*\"\,\"__typename\":\"Genre\"'
	regex[actor1]='\,\"actor\":\['
	regex[actor2]='\"@type\":\"Person\",\"url\":\".*\"\,\"name\":\"(.*)\"'
	regex[director1]='\]\,\"director\":\['
	regex[director2]='\"@type\":\"Person\",\"url\":\".*\"\,\"name\":\"(.*)\"'
	regex[runtime1]='\,\"runtime\":'
	regex[runtime2]='\"seconds\":(.*)\,\"displayableProperty\":'

	agent='Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36'

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

		(( z += 1 ))

# If current JSON type is not a list, match the regex and return from
# this function.
		if [[ -z ${lists[${json_type}]} ]]; then
			if [[ ${tmp_array[${z}]} =~ ${regex[${json_type}2]} ]]; then
				imdb_info["${json_type}"]="${BASH_REMATCH[1]}"
			fi

			return
		fi

# This loop parses JSON lists.
		while [[ ${tmp_array[${z}]} =~ ${regex[${json_type}2]} ]]; do
			list+=("${BASH_REMATCH[1]}")

			(( z += 1 ))

			if [[ ${tmp_array[${z}]} =~ ${regex[list]} ]]; then
				(( z += 1 ))
			else
				(( z -= 1 ))
				break
			fi
		done

		string=$(printf '%s, ' "${list[@]}")
		string="${string%, }"

		imdb_info["${json_type}"]="$string"
	}

	if [[ ${term[-1]} =~ ${regex[y]} ]]; then
		y="${BASH_REMATCH[1]}"
		unset -v term[-1]
	fi

	t=$(uriencode "${term[@]}")

# Sets the type of IMDb search results to include.

# All currently available types:
# feature,tv_series,short,tv_episode,tv_miniseries,tv_movie,tv_special,
# tv_short,video_game,video,music_video,podcast_series,podcast_episode
	type='feature,tv_series,tv_miniseries,tv_movie,tv_special,video'

# If the $y variable is empty, that means the year is unknown, hence we
# will need to use slightly different URLs, when searching for the
# movie.
	if [[ -z $y ]]; then
		url_tmp="https://www.imdb.com/search/title/?title=${t}&title_type=${type}"
	else
		url_tmp="https://www.imdb.com/search/title/?title=${t}&title_type=${type}&release_date=${y}-01-01,${y}-12-31"
	fi

	id=$(get_page "$url_tmp" | sed -nE "s/${regex[id]}.*$/\1/;s/^.*${regex[id]}/\1/p")

	if [[ -z $id ]]; then
		return 1
	fi

	url="https://www.imdb.com/${id}/"

# Translate {} characters to newlines so we can parse the JSON data.
# I came to the conclusion that this is the most simple, reliable and
# future-proof way to get the movie information. It's possible to add
# more regex:es to the for loop below, to get additional information.
# Excluding lines that are longer than 500 characters, to make it
# slightly faster.
	mapfile -t tmp_array < <(get_page "$url" | tr '{}' '\n' | grep -Ev -e '.{500}' -e '^[[:blank:]]*$')

	json_types=(['title']=1 ['year']=1 ['plot']=1 ['rating']=1 ['genre']=1 ['actor']=1 ['director']=1 ['runtime']=1)

	for (( z = 0; z < ${#tmp_array[@]}; z++ )); do
		if [[ ${#json_types[@]} -eq 0 ]]; then
			break
		fi

		for json_type in "${!json_types[@]}"; do
			if [[ ! ${tmp_array[${z}]} =~ ${regex[${json_type}1]} ]]; then
				continue
			fi

			get_list

			unset -v json_types["${json_type}"]
			break
		done
	done

	printf '%s\n' "${imdb_info[title]}"
	printf '%s\n' "${imdb_info[year]}"
}

# Creates a function, called 'check_regex', which will split lines based
# on a delimiter, and check each word against a regex.
check_regex () {
	declare word
	declare -a words match

	regex[tmp]="$2"

	mapfile -d',' -t words <<<"$1"
	words[-1]="${words[-1]%$'\n'}"

	for (( z = 0; z < ${#words[@]}; z++ )); do
		word="${words[${z}]}"

		if [[ $word =~ ${regex[blank]} ]]; then
			word="${BASH_REMATCH[1]}"
		fi

		if [[ ! $word =~ ${regex[tmp]} ]]; then
			continue
		fi

		match=("${BASH_REMATCH[@]:1}")

		if [[ ${#match[@]} -gt 0 ]]; then
			printf '%s\n' "${match[@]}"
		fi

		return 0
	done

	return 1
}

# Creates a function, called 'dts_extract_remux', which will find a
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
	declare high_kbps low_kbps high_bps low_bps bps_limit use_kbps
	declare map_ref map_use_ref lang_ref stream_ref track_ref bitrate_ref channel_ref
	declare audio_format args_string line type_tmp
	declare -a audio_types if_info_tmp args1
	declare -A type elements audio_tracks audio_maps audio_channels

	high_kbps='1536'
	low_kbps='768'
	high_bps='1537000'
	low_bps='769000'
	bps_limit=$(( (high_bps - low_bps) / 2 ))
	use_kbps="${high_kbps}k"

	type[dts_hdma]='^dts \(DTS-HD MA\)'
	type[truehd]='^truehd'
	type[pcm]='^pcm_bluray'
	type[flac]='^flac'
	type[dts]='^dts \(DTS(-ES){0,1}\)'
	type[ac3]='^ac3'
	elements[dts_hdma]=0
	elements[truehd]=0
	elements[pcm]=0
	elements[flac]=0
	elements[dts]=0
	elements[ac3]=0

	audio_types=('dts_hdma' 'truehd' 'pcm' 'flac' 'dts' 'ac3')

	if_info_tmp=("${if_info[@]}")

# Creates a function, called 'parse_ffmpeg', which will parse the output
# from ffmpeg, get all the streams and bitrates.
	parse_ffmpeg () {
		declare n lang_tmp bps_last this next line
		declare -a streams_tmp

		streams=()
		maps=()
		langs=()
		bitrates=()

		for (( i = 0; i < ${#if_info_tmp[@]}; i++ )); do
			line="${if_info_tmp[${i}]}"

			declare bps

# Check if line is a stream.
			if [[ ! $line =~ ${regex[stream1]} ]]; then
				continue
			fi

			if [[ -z $n ]]; then
				n=0
			else
				(( n += 1 ))
			fi

			streams_tmp["${n}"]="$i"
			maps["${n}"]="${BASH_REMATCH[1]}"
			langs["${n}"]='und'

# Parse line again to get additional information.
			if [[ ! $line =~ ${regex[stream2]} ]]; then
				continue
			fi

			lang_tmp=$(tr -d '[:punct:]' <<<"${BASH_REMATCH[1],,}")

			if [[ -n $lang_tmp ]]; then
				langs["${n}"]="$lang_tmp"
			fi

			case "${BASH_REMATCH[2]}" in
				'Video')
					streams["${n},v"]="${BASH_REMATCH[3]}"
				;;
				'Audio')
					streams["${n},a"]="${BASH_REMATCH[3]}"
				;;
				'Subtitle')
					streams["${n},s"]="${BASH_REMATCH[3]}"
				;;
				*)
					continue
				;;
			esac

# If stream line contains bitrate, use that.
			bps=$(check_regex "${BASH_REMATCH[3]}" "${regex[kbps]}")

			if [[ $? -eq 0 ]]; then
				(( bps *= 1000 ))
				bitrates["${n}"]="$bps"

				unset -v bps
			fi
		done

		for (( i = 0; i < ${#streams_tmp[@]}; i++ )); do
			(( j = i + 1 ))

			this="${streams_tmp[${i}]}"
			next="${streams_tmp[${j}]}"

			declare bps

			if [[ -z $next ]]; then
				(( next = ${#if_info_tmp[@]} - 1 ))
			fi

			if [[ -n ${bitrates[${i}]} ]]; then
				continue
			fi

			while [[ $this -lt $next ]]; do
				(( this += 1 ))

				line="${if_info_tmp[${this}]}"

				if [[ $line =~ ${regex[bps]} ]]; then
					bps="${BASH_REMATCH[1]}"
					break
				fi
			done

			if [[ -z $bps ]]; then
				continue
			fi

# If input bitrate consists of at least 4 digits, get the last 3 digits.
			if [[ $bps =~ ${regex[last3]} ]]; then
				bps_last="${BASH_REMATCH[1]}"

				if [[ $bps_last =~ ${regex[zero]} ]]; then
					bps_last="${BASH_REMATCH[1]}"
				fi

				(( bps -= bps_last ))

# If the last 3 digits are equal to (or higher than) 500, then round up
# that number, otherwise round it down.
				if [[ $bps_last -ge 500 ]]; then
					(( bps += 1000 ))
				fi
			fi

			bitrates["${i}"]="$bps"

			unset -v bps
		done
	}

# Creates a function, called 'get_bitrate', which will decide what DTS
# bitrate to use for the output file.
	get_bitrate () {
		declare bps_if

# If $audio_format is 'flac', we will decode the FLAC audio track in
# order to get the correct (uncompressed) bitrate, which will later be
# used to calculate the output bitrate.
		if [[ $audio_format == 'flac' ]]; then
			of[flac_fn]="${of[dn]}/FLAC.TMP-${session}.flac"
			of[wav_fn]="${of[dn]}/FLAC.TMP-${session}.wav"

# Extracts the FLAC track from $if, and decodes it to WAV.
			args=("${cmd[1]}" -i \""${if[fn]}"\" -map "${!map_use_ref}" -c:a copy \""${of[flac_fn]}"\")
			run_or_quit
			args=("${cmd[4]}" -d \""${of[flac_fn]}"\")
			run_or_quit
			args=(rm -f \""${of[flac_fn]}"\")
			run_or_quit

# Gets information about the WAV file.
			mapfile -t if_info_tmp < <(eval "${cmd[1]}" -hide_banner -i \""${of[wav_fn]}"\" 2>&1)
			args=(rm -f \""${of[wav_fn]}"\")
			run_or_quit

			parse_ffmpeg

			for (( i = 0; i < ${#maps[@]}; i++ )); do
				stream_ref="streams[${i},a]"
				bitrate_ref="bitrates[${i}]"

# Check if the current stream is an audio track.
				if [[ -z ${!stream_ref} ]]; then
					continue
				fi

# Save the bitrate.
				bps_if="${!bitrate_ref}"
				break
			done
		else
			for (( i = 0; i < ${#maps[@]}; i++ )); do
				map_ref="maps[${i}]"
				bitrate_ref="bitrates[${i}]"

# Check if the current stream matches the chosen audio track.
				if [[ ${!map_ref} != "${!map_use_ref}" ]]; then
					continue
				fi

# Save the bitrate.
				bps_if="${!bitrate_ref}"
				break
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
			(( bps_diff = high_bps - bps_if ))

# If the difference is greater than $bps_limit, then set the $use_kbps
# variable to $low_kbps.
			if [[ $bps_diff -ge $bps_limit ]]; then
				use_kbps="${low_kbps}k"
			fi
		fi

		if_info_tmp=("${if_info[@]}")
		parse_ffmpeg
	}

	parse_ffmpeg

# Go through the audio streams in the input file information, and see if
# they match the types of audio we're looking for.
	for (( i = 0; i < ${#maps[@]}; i++ )); do
		stream_ref="streams[${i},a]"
		map_ref="maps[${i}]"
		lang_ref="langs[${i}]"

# Check if the current stream is an audio track.
		if [[ -z ${!stream_ref} ]]; then
			continue
		fi

# Check if the current stream has the right language (or no language).
		if [[ ! ${!lang_ref} =~ ${regex[lang2]} ]]; then
			continue
		fi

# Check if the current stream has the right format. If so, save it.
		for type_tmp in "${audio_types[@]}"; do
			n="elements[${type_tmp}]"

			check_regex "${!stream_ref}" "${type[${type_tmp}]}"

			if [[ $? -ne 0 ]]; then
				continue
			fi

			audio_tracks["${type_tmp},${!n}"]="${!stream_ref}"
			audio_maps["${type_tmp},${!n}"]="${!map_ref}"
			(( elements[${type_tmp}] += 1 ))
			break
		done
	done

# Go through the different types of audio and see if we have matching
# surround tracks in those formats.
	for type_tmp in "${audio_types[@]}"; do
		for (( i = 0; i < ${elements[${type_tmp}]}; i++ )); do
			track_ref="audio_tracks[${type_tmp},${i}]"

			declare channel

			audio_channels["${type_tmp},${i}"]=0

			channel=$(check_regex "${!track_ref}" "${regex[surround]}")

			if [[ $? -ne 0 ]]; then
				continue
			fi

			audio_channels["${type_tmp},${i}"]="$channel"

			unset -v channel
		done
	done

# Go through the format priority list in descending order, and pick the
# audio track that has the highest number of channels (if possible).
	for type_tmp in "${audio_types[@]}"; do
		declare map channel
		channel=0

		for (( i = 0; i < ${elements[${type_tmp}]}; i++ )); do
			track_ref="audio_tracks[${type_tmp},${i}]"
			map_ref="audio_maps[${type_tmp},${i}]"
			channel_ref="audio_channels[${type_tmp},${i}]"

			if [[ ${!channel_ref} -gt $channel ]]; then
				map="$map_ref"
				channel="${!channel_ref}"
			fi
		done

		if [[ $channel -ge 5 ]]; then
			map_use_ref="$map"
			audio_format="$type_tmp"
			break
		fi

		unset -v map channel
	done

# Pick the first audio track in the list, in the preferred available
# format, if $map_use_ref is still empty.
	if [[ -z $map_use_ref ]]; then
		for type_tmp in "${audio_types[@]}"; do
			if [[ ${elements[${type_tmp}]} -eq 0 ]]; then
				continue
			fi

			map_use_ref="audio_maps[${type_tmp},0]"
			audio_format="$type_tmp"
			break
		done
	fi

	if [[ -z $map_use_ref ]]; then
		cat <<NO_MATCH

${if[fn]}

There are no suitable audio tracks in input file. It either has no audio
tracks at all, or they're in the wrong format or have the wrong language
code. A possible fix is checking the language of the input file, and
specifying the correct language code as argument to the script.

Listing all streams found in input file:

NO_MATCH
		for (( i = 0; i < ${#if_info_tmp[@]}; i++ )); do
			line="${if_info_tmp[${i}]}"

			if [[ ! $line =~ ${regex[stream1]} ]]; then
				continue
			fi

			printf '%s\n' "$line"
		done

		printf '\n'

		exit
	fi

# Creates first part of ffmpeg command.
	args1=("${cmd[1]}" -i \""${if[fn]}"\" -metadata title=\"\" -map 0:v -map "${!map_use_ref}" -map 0:s?)

# Creates ffmpeg command.
	case "$audio_format" in
		'dts_hdma')
			args=("${args1[@]}" -bsf:a dca_core -c:v copy -c:a copy -c:s copy \""${of[remux_fn]}"\")
		;;
		'truehd')
			args=("${args1[@]}" -strict -2 -c:v copy -c:a dts -c:s copy -ab "${use_kbps}" \""${of[remux_fn]}"\")
		;;
		'pcm')
			get_bitrate
			args=("${args1[@]}" -strict -2 -c:v copy -c:a dts -c:s copy -ab "${use_kbps}" \""${of[remux_fn]}"\")
		;;
		'flac')
			get_bitrate
			args=("${args1[@]}" -strict -2 -c:v copy -c:a dts -c:s copy -ab "${use_kbps}" \""${of[remux_fn]}"\")
		;;
		'dts')
			args=("${args1[@]}" -c:v copy -c:a copy -c:s copy \""${of[remux_fn]}"\")
		;;
		'ac3')
			get_bitrate
			args=("${args1[@]}" -strict -2 -c:v copy -c:a dts -c:s copy -ab "${use_kbps}" \""${of[remux_fn]}"\")
		;;
	esac

# Runs ffmpeg, extracts the core DTS track, and remuxes.
	args_string="${args[@]}"
	printf '\r\n%s\r\n' 'Command used to extract core DTS track, and remux:' | tee --append "${of[command_fn]}"
	printf '%s\r\n' "$args_string" | tee --append "${of[command_fn]}"

	if [[ $exist -ne 1 ]]; then
# Runs ffmpeg. If the command wasn't successful, quit.
		run_or_quit
	fi
}

# Creates a function, called 'hb_encode', which will generate a full
# HandBrake command (with args), and then execute it.
hb_encode () {
	declare args_string
	declare -a args1 args2 args3

	args1=("${cmd[0]}" --format "${format}" --markers --encoder "${v_encoder}" --encoder-preset "${preset}")

	if [[ $hb_subs -eq 1 ]]; then
		args2=(--vb "${v_bitrate}" --two-pass --vfr --aencoder "${a_encoder}" --all-subtitles -i \""${of[remux_fn]}"\" -o \""${of[fn]}"\")
	else
		args2=(--vb "${v_bitrate}" --two-pass --vfr --aencoder "${a_encoder}" -i \""${of[remux_fn]}"\" -o \""${of[fn]}"\")
	fi

	args3=(2\> \>\(tee \""${of[hb_log_fn]}"\"\))

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
	printf '\r\n%s\r\n' 'Command used to encode:' | tee --append "${of[command_fn]}"
	printf '%s\r\n' "$args_string" | tee --append "${of[command_fn]}"

# Runs HandBrake. If the command wasn't successful, quit.
	run_or_quit
}

# Creates a function, called 'sub_mux', which will remux the finished
# encode with the subtitles from '$of[remux_fn]'.
sub_mux () {
	declare args_string
	declare -a if_subs

	mapfile -t if_subs < <(mkvinfo "${of[remux_fn]}" 2>&- | grep 'Track type: subtitles')

	if [[ ${#if_subs[@]} -eq 0 ]]; then
		return
	fi

	args=("${cmd[2]}" --title \"\" -o \""${of[tmp_fn]}"\" \""${of[fn]}"\" --no-video --no-audio --no-chapters \""${of[remux_fn]}"\")

	args_string="${args[@]}"
	printf '\r\n%s\r\n' 'Commands used to merge with subtitles:' | tee --append "${of[command_fn]}"
	printf '%s\r\n' "$args_string" | tee --append "${of[command_fn]}"

	run_or_quit

	args=(mv \""${of[tmp_fn]}"\" \""${of[fn]}"\")

	args_string="${args[@]}"
	printf '\r\n%s\r\n' "$args_string" | tee --append "${of[command_fn]}"

	run_or_quit
}

# Creates a function, called 'info_txt', which creates info txt files
# containing information generated by ffmpeg. It creates a separate txt
# file for input file, output file and remux output. If the mediainfo
# command is installed, a text file containing information from that
# will also be created.
info_txt () {
	declare txt_ref info_ref type
	declare -a info_list1 info_list2 info_list3
	declare -a of_info of_remux_info hb_version_info hb_opts_info ff_version_info ff_opts_info size_info mediainfo_info
	declare -A info

	cmd[5]=$(basename "$(command -v "mediainfo")")

# Creates file names for the info txt files, which contain the
# information generated by 'ffmpeg'. Also creates file names for
# HandBrake version and options, and file names for ffmpeg version and
# options.
	info[if]="${of[info_dn]}/${if[bn]}_info.txt"
	info[of]="${of[info_dn]}/${of[bn]}.mkv_info.txt"
	info[of_remux]="${of[info_dn]}/${of[remux_bn]}.mkv_info.txt"
	info[hb_version]="${of[info_dn]}/${cmd[0]}_version.txt"
	info[hb_opts]="${of[info_dn]}/${cmd[0]}_options.txt"
	info[ff_version]="${of[info_dn]}/${cmd[1]}_version.txt"
	info[ff_opts]="${of[info_dn]}/${cmd[1]}_options.txt"
	info[size]="${of[info_dn]}/size.txt"
	info[mediainfo]="${of[info_dn]}/${of[bn]}_mediainfo.txt"

	if [[ -n ${cmd[5]} ]]; then
		info_list1=('if' 'of' 'of_remux' 'mediainfo')
	else
		info_list1=('if' 'of' 'of_remux')
	fi

	info_list2=('hb_version' 'hb_opts' 'ff_version' 'ff_opts' 'size')
	info_list3=("${info_list1[@]}" "${info_list2[@]}")

# If the info txt file names (in list 1) already exist, add a random
# number to the end of the file name.
	for type in "${info_list1[@]}"; do
		txt_ref="info[${type}]"

		if [[ ! -f ${!txt_ref} ]]; then
			continue
		fi

		eval info["${type}"]="${!txt_ref%.*}-${session}.txt"
	done

# Gets information about output file.
# Gets information about remux output file.
# Gets the HandBrake version.
# Gets the HandBrake options.
# Gets the ffmpeg version.
# Gets the ffmpeg options.
# Gets the file size of '$if[fn]', '$of[remux_fn]' and '$of[fn]'.
# Gets information about output file from 'mediainfo'.
	mapfile -t of_info < <(eval "${cmd[1]}" -hide_banner -i \""${of[fn]}"\" 2>&1)
	mapfile -t of_remux_info < <(eval "${cmd[1]}" -hide_banner -i \""${of[remux_fn]}"\" 2>&1)
	mapfile -t hb_version_info < <(eval "${cmd[0]}" --version 2>&-)
	mapfile -t hb_opts_info < <(eval "${cmd[0]}" --help 2>&-)
	mapfile -t ff_version_info < <(eval "${cmd[1]}" -version)
	mapfile -t ff_opts_info < <(eval "${cmd[1]}" -hide_banner -help full)
	mapfile -t size_info < <(du -BM "${if[fn]}" "${of[remux_fn]}" "${of[fn]}" 2>&-)
	mapfile -t mediainfo_info < <(eval "${cmd[5]}" -f \""${of[fn]}"\" 2>&-)

# Prints the information gathered from the input file, by ffmpeg.
# Prints the information gathered from the output file, by ffmpeg.
# Prints the information gathered from the remux output file, by ffmpeg.
# Prints the version and options of HandBrake.
# Prints the version and options of ffmpeg.
# Prints file size information.
# Prints the information gathered from the output file, by mediainfo
# (if that command is installed).
	for type in "${info_list3[@]}"; do
		txt_ref="info[${type}]"
		info_ref="${type}_info[@]"

		printf '%s\r\n' "${!info_ref}" > "${!txt_ref}"
	done
}

# Creates a function, called 'run_or_quit', which will run any command
# stored in the 'args' array, and quit if the command returns a false
# exit status.
run_or_quit () {
	eval "${args[@]}" || exit "$?"
}

# Creates a function, called 'check_res', which will check the
# resolution of the input file, to see if it's 1080p, which is the
# resolution we want when using this script.
check_res () {
	declare switch stream_ref if_res

	switch=0

# Go through the video streams in the input file information, and see if
# they match the type of video we're looking for.
	for (( i = 0; i < ${#maps[@]}; i++ )); do
		stream_ref="streams[${i},v]"

# Check if the current stream is a video track.
		if [[ -z ${!stream_ref} ]]; then
			continue
		fi

# Check if the current stream has the correct resolution.
		if_res=$(check_regex "${!stream_ref}" "${regex[res]}")

		if [[ $? -ne 0 ]]; then
			continue
		fi

		if [[ $if_res -ne 1920 ]]; then
			switch=1
		fi

		break
	done

	if [[ $switch -eq 1 ]]; then
		printf '\n%s\n\n' "Wrong horizontal resolution (${if_res}) in input file!"
		printf '%s\n\n' "Resolution needs to be 1080p (1920x1080)!"
		exit
	fi
}

# Creates a function, called 'is_handbrake', which will check if there
# are any running HandBrake processes, and if so, wait.
is_handbrake () {
	declare pid comm
	declare -a hb_pids

	args=(ps -C "${cmd[0]}" -o pid=,args=)

# Checks if HandBrake is running.
	mapfile -t hb_pids < <(eval "${args[@]}")

# Prints the PID and arguments of the HandBrake commands that are
# running, if any.
	if [[ ${#hb_pids[@]} -gt 0 ]]; then
		printf '\n%s\n\n' 'Waiting for this to finish:'

		for (( i = 0; i < ${#hb_pids[@]}; i++ )); do
			if [[ ! ${hb_pids[${i}]} =~ ${regex[pid_comm]} ]]; then
				continue
			fi

			pid="${BASH_REMATCH[1]}"
			comm="${BASH_REMATCH[2]}"

			printf '%s: %s\n' 'PID' "$pid"
			printf '%s: %s\n\n' 'COMMAND' "$comm"
		done
	fi

# Starts the loop that will wait for HandBrake to finish.
	while [[ ${#hb_pids[@]} -gt 0 ]]; do
# Sleeps for 5 seconds.
		sleep 1

# Checks again if HandBrake is running.
		mapfile -t hb_pids < <(eval "${args[@]}")
	done
}

# Creates a function, called 'if_m2ts', which will be called if input
# file is an M2TS, in the directory structure '/BDMV/STREAM/'. The
# function outputs a name, which can be used with the 'break_name'
# function, to get the movie information from IMDb. If the input file
# name doesn't match the regex, return from this function, hence leaving
# the $if_m2ts variable empty.
if_m2ts () {
	declare field
	declare -a path_parts

	if [[ ! ${if[fn]} =~ ${regex[m2ts]} ]]; then
		return
	fi

	mapfile -d'/' -t path_parts <<<"${if[fn]}"
	(( field = ${#path_parts[@]} - 4 ))
	if[m2ts_bn]="${path_parts[${field}]}"
}

# Creates a function, called 'get_name', which will get the movie title
# and year, based on the input file name.
get_name () {
	declare bname
	declare -a bname_tmp imdb_tmp

	bname="${if[bn]}"

# If the input file name is an M2TS, get the movie title and year from
# the surrounding directory structure.
	if_m2ts

	if [[ -n ${if[m2ts_bn]} ]]; then
		bname="${if[m2ts_bn]}"
	fi

# Breaks up the input file name, and gets its IMDb name.
	mapfile -t bname_tmp < <(break_name "$bname")

	title="${bname_tmp[0]}"
	year="${bname_tmp[1]}"

# Gets information from IMDb.
	if [[ $year != '0000' ]]; then
		mapfile -t imdb_tmp < <(imdb "${title} (${year})")
	else
		mapfile -t imdb_tmp < <(imdb "$title")
	fi

# If IMDb lookup succeeded, use that information.
# If not, use the information in the 'bname_tmp' array instead.
	if [[ -n ${imdb_tmp[0]} ]]; then
		title="${imdb_tmp[0]}"
		year="${imdb_tmp[1]}"
	fi

# Deletes special characters from the title, and translates spaces to
# dots.
	title=$(fsencode "$title" | tr ' ' '.')
}

# Creates a function, called 'is_torrent', which checks if the file name
# ends with '.part', or if there's a file name in the same directory
# that ends with '.part'. If there is, wait until the file name changes,
# and '.part' is removed from the file name. This function recognizes if
# input file is an unfinished download, and waits for the file to fully
# download before processing it.
is_torrent () {
	declare md5

	if [[ ${if[fn]} =~ ${regex[part]} ]]; then
		if[tmp_fn]="${if[fn]}"
	else
		if[tmp_fn]="${if[fn]}.part"
	fi

	if [[ ! -f ${if[tmp_fn]} ]]; then
		return
	fi

	printf '\n%s\n' 'Waiting for this download to finish:'
	printf '%s\n\n' "${if[tmp_fn]}"

	while [[ -f ${if[tmp_fn]} ]]; do
		sleep 1
	done

	sync

	if[fn]="${if[fn]%.part}"

	md5=$(md5sum -b "${if[fn]}")
	of[md5_fn]="${HOME}/${if[bn]}_MD5-${session}.txt"

	printf '%s\r\n' "$md5" | tee "${of[md5_fn]}"
}

check_cmd

is_torrent

# Gets information about input file.
mapfile -t if_info < <(eval "${cmd[1]}" -hide_banner -i \""${if[fn]}"\" 2>&1)

# Gets the movie title and year.
get_name

# Creates a directory structure in the current user's home directory:
# "${title}.${year}.${rls_type}/Info"
of[bn]="${title}.${year}.${rls_type}"
of[remux_bn]="${title}.${year}.REMUX"
of[dn]="${of[dn]}/${of[bn]}"
of[info_dn]="${of[dn]}/Info"

mkdir -p "${of[info_dn]}"

# Creates the output file name, as well as the remux output file name.
of[fn]="${of[dn]}/${of[bn]}.mkv"
of[tmp_fn]="${of[dn]}/${of[bn]}.TMP-${session}.mkv"
of[remux_fn]="${of[dn]}/${of[remux_bn]}.mkv"

# Creates a file name which will contain the commands run by this
# script. Also creates a file name that will store the output from
# HandBrake. If the file name already exists, delete that file, and then
# create a new one.
of[command_fn]="${of[info_dn]}/${title}.${year}_commands.txt"
of[hb_log_fn]="${of[info_dn]}/${title}.${year}_HandBrake_log.txt"

for txt_fn in "${of[command_fn]}" "${of[hb_log_fn]}"; do
	if [[ -f $txt_fn ]]; then
		rm -f "$txt_fn"
	fi

	touch "$txt_fn"
done

if [[ $exist -ne 1 ]]; then
# If output file name already exists, add a random number to the end of
# the file name.
	if [[ -f ${of[fn]} ]]; then
		of[fn]="${of[dn]}/${of[bn]}-${session}.mkv"
	elif [[ -f ${of[remux_fn]} ]]; then
		of[remux_fn]="${of[dn]}/${of[remux_bn]}-${session}.mkv"
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
