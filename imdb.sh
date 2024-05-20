#!/bin/bash

# This script looks up movies on IMDb, and displays information about
# them.

# Usage: imdb.sh "movie title (year)"

# (The year is optional, and only recommended for more accurate search
# results. The paranthesis around (year) are required for proper
# parsing.)

# Creates a function, called 'usage', which will print usage
# instructions and then quit.
usage () {
	printf '\n%s\n\n' "Usage: $(basename "$0") \"movie title (year)\""
	exit
}

if [[ $# -eq 0 ]]; then
	usage
fi

declare -A regex

# Creates a function, called 'uriencode', which will translate the
# special characters in any string to be URL friendly. This will be
# used in the 'imdb' function.
uriencode () {
	declare url_string

	url_string="$@"

	curl -Gso /dev/null -w %{url_effective} --data-urlencode "$url_string" 'http://localhost' | sed -E 's/^.{18}(.*)$/\1/'
}

# Creates a function, called 'time_calc', which will translate seconds
# into the hh:mm:ss format.
time_calc () {
	declare s m h

	s="$1"

	m=$(( s / 60 ))
	h=$(( m / 60 ))

	s=$(( s % 60 ))
	m=$(( m % 60 ))

	printf '%02d:%02d:%02d' "$h" "$m" "$s"
}

# Creates a function, called 'imdb', which will look up the movie name
# on IMDb. https://www.imdb.com/search/title/
# https://www.imdb.com/interfaces/
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

	imdb_info[runtime]=$(time_calc "${imdb_info[runtime]}")

	cat <<IMDB

${imdb_info[title]} (${imdb_info[year]})
${url}

Rating: ${imdb_info[rating]}

Genre(s): ${imdb_info[genre]}

Runtime: ${imdb_info[runtime]}

Plot summary:
${imdb_info[plot]}

Actor(s): ${imdb_info[actor]}

Director(s): ${imdb_info[director]}

IMDB
}

imdb "$@"
