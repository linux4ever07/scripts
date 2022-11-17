#!/bin/bash

# This script looks up movies on IMDb, and displays information about
# them.

# Usage: imdb.sh "movie title (year)"

# (The year is optional, and only recommended for more accurate search
# results. The paranthesis around (year) are required for proper
# parsing.)

usage () {
	printf '\n%s\n\n' "Usage: $(basename "$0") \"movie title (year)\""
	exit
}

if [[ $# -eq 0 ]]; then
	usage
fi

# This creates a function called 'uriencode', which will translate
# the special characters in any string to be URL friendly. This will be
# used in the 'imdb' function.
uriencode () {
	curl -Gso /dev/null -w %{url_effective} --data-urlencode @- "" <<<"$@" | sed -E 's/..(.*).../\1/'
}

# Creates a function called 'time_calc', which will translate seconds
# into the hh:mm:ss format.
time_calc () {
	s="$1"
	m=0
	h=0

# While $s (seconds) is equal to (or greater than) 60, clear the $s
# variable and add 1 to the $m (minutes) variable.
	while [[ $s -ge 60 ]]; do
		m=$(( m + 1 ))
		s=$(( s - 60 ))
	done

# While $m (minutes) is equal to (or greater than) 60, clear the $m
# variable and add 1 to the $h (hours) variable.
	while [[ $m -ge 60 ]]; do
		h=$(( h + 1 ))
		m=$(( m - 60 ))
	done

# While $h (hours) is equal to 100 (or greater than), clear the $h
# variable.
	while [[ $h -ge 100 ]]; do
		h=$(( h - 100 ))
	done

	printf '%02d:%02d:%02d' "$h" "$m" "$s"
}

# This creates a function called 'imdb', which will look up the movie
# name on IMDb.
# https://www.imdb.com/search/title/
# https://www.imdb.com/interfaces/
imdb () {
	if [[ $# -eq 0 ]]; then
		return 1
	fi

	mapfile -d' ' -t term < <(sed -E 's/[[:blank:]]+/ /g' <<<"$@")
	term[-1]="${term[-1]%$'\n'}"

	y_regex='^\(([0-9]{4})\)$'

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
	actor_regex1='\,\"actor\":\['
	actor_regex2='\"@type\":\"Person\",\"url\":\".*\"\,\"name\":\"(.*)\"'
	director_regex1='\]\,\"director\":\['
	director_regex2='\"@type\":\"Person\",\"url\":\".*\"\,\"name\":\"(.*)\"'
	runtime_regex1='\,\"runtime\":'
	runtime_regex2='\"seconds\":(.*)\,\"__typename\":\"Runtime\"'

	agent='Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/103.0.0.0 Safari/537.36'

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

	mapfile -t id_array < <(get_page "$url_tmp" | grep -Eo "$id_regex" | sed -E "s/${id_regex}/\1/")
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

	runtime=$(time_calc "$runtime")

	cat <<IMDB

${title} (${year})
${url}

Rating: ${rating}

Genre(s): ${genre}

Runtime: ${runtime}

Plot summary:
${plot}

Actor(s): ${actor}

Director(s): ${director}

IMDB
}

imdb "$@"
