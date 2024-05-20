#!/bin/bash

# This script parses movie file names.

# It has 2 modes, 'parse' and 'find'.

# In 'parse' mode, it will only parse the file name to extract the movie
# title and year.

# In 'find' mode, it will check if the file name matches scene rules
# and is the type of video file we're looking for (aka a movie rip).

# This script is just to remove the need for me to store the
# 'break_name' function separately in other scripts. If I need to make
# changes to this function, I only have to do it in one place.

declare mode query_string
declare -a query

declare array_ref number_ref elements type_tmp
declare -a bname_dots bname_hyphens bname_underscores bname_spaces

declare -A regex

regex[blank]='^[[:blank:]]*(.*)[[:blank:]]*$'
regex[year]='^([[:punct:]]|[[:blank:]]){0,1}([0-9]{4})([[:punct:]]|[[:blank:]]){0,1}$'

while [[ $# -gt 0 ]]; do
	case "$1" in
		'-parse')
			mode='parse'

			shift
		;;
		'-find')
			mode='find'

			shift
		;;
		*)
			query+=("$1")

			shift
		;;
	esac
done

query_string="${query[@]}"

# Creates a function, called 'break_name', which will break up the input
# file name.
break_name () {
	declare bname type
	declare -a types
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
}

# Creates a function, called 'break_name_parse', which will extract the
# movie title, and year.
break_name_parse () {
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

# Creates a function, called 'break_name_find', which tries to match
# a file name against the words in 'rip' array. It prints the number of
# matches.
break_name_find () {
	declare count tag
	declare -a rip

	count=0

# Creates an array with all the different scene tags to look for in
# each file name.
	rip=(720p 1080p 2160p screener hc dvb hdtv tvrip webrip webdl web-dl hddvd hd-dvd bluray blu-ray bdrip dvdrip divx xvid h264 x264 avc h265 x265 hevc dts ac3 pcm vorbis aac mp3)

# This for loop goes through the word list, and compares each
# word with the words in 'rip' array.
	for (( i = 0; i < elements; i++ )); do
		array_ref="bname_${type_tmp}[${i}]"

		if [[ -z ${!array_ref} ]]; then
			continue
		fi

		for tag in "${rip[@]}"; do
			if [[ ${!array_ref,,} =~ $tag ]]; then
				(( count += 1 ))
				break
			fi
		done
	done

	printf '%s' "$count"
}

break_name "$query_string"

case "$mode" in
	'parse')
		break_name_parse
	;;
	'find')
		break_name_find
	;;
esac
