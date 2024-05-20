#!/bin/bash

# This script is meant to find duplicate movie rips on my drives.
# It will only search for file names that match scene rules.

# The script has 2 modes, 'name' (default) and 'imdb' (optional).

# In 'name' mode, the file names will be lowercased and parsed to
# extract the movie title and year.

# In 'imdb' mode, the script will try to find the movie on IMDb to get a
# better match, even if the file names contain slight differences.

# To search all drives in 'name' mode:
# find_movie_dups.sh "${HOME}" "/run/media/${USER}"

# To do the same in 'imdb' mode:
# find_movie_dups.sh -imdb "${HOME}" "/run/media/${USER}"

# A recent version of 'break_name.sh' is required to be located in the
# same directory as this script.

declare mode count key
declare -a dirs files_in files_out
declare -A if movie regex

regex[prune]="^\/run\/media\/${USER}\/[[:alnum:]]{8}-[[:alnum:]]{4}-[[:alnum:]]{4}-[[:alnum:]]{4}-[[:alnum:]]{12}\/extracted_subs"
regex[720p]='\(([0-9]{3,4})p_h\.264-aac\)'
regex[1080p]='\(([0-9]{3,4})p_([0-9]{1,2})fps_(h264|av1)-([0-9]{2,3})kbit_(aac|opus)\)'

mode='name'

# Creates a function, called 'usage', which will print usage
# instructions and then quit.
usage () {
	cat <<USAGE

Usage: $(basename "$0") [arg] [dirs...]

	Optional arguments:

-imdb
	Find movie titles on IMDb.

USAGE

	exit
}

# The loop below handles the arguments to the script.
while [[ $# -gt 0 ]]; do
	case "$1" in
		'-imdb')
			mode='imdb'

			shift
		;;
		*)
			if [[ -d $1 ]]; then
				dirs+=("$(readlink -f "$1")")

				shift
			else
				usage
			fi
		;;
	esac
done

if [[ ${#dirs[@]} -eq 0 ]]; then
	usage
fi

# Creates a function, called 'break_name_find', which tries to match
# a file name against the words in 'rip' array. It prints the number of
# matches.
break_name_find () {
	break_name.sh -find "$1"
}

# Creates a function, called 'break_name_parse', which will extract the
# movie title, and year.
break_name_parse () {
	break_name.sh -parse "$1"
}

# Creates a function, called 'uriencode', which will translate the
# special characters in any string to be URL friendly. This will be
# used in the 'imdb' function.
uriencode () {
	declare url_string

	url_string="$@"

	curl -Gso /dev/null -w %{url_effective} --data-urlencode "$url_string" 'http://localhost' | sed -E 's/^.{18}(.*)$/\1/'
}

# Creates a function, called 'imdb', which will look up the movie
# name on IMDb, based on the file name of the input file.
# https://www.imdb.com/search/title/
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

	cat <<IMDB
${imdb_info[title]}
${imdb_info[year]}
${url}
${id}
IMDB
}

# Creates a function, called 'set_names', which will create variables
# for file names.
set_names () {
	if[fn]="$1"

	if[bn]=$(basename "${if[fn]}")
	if[bn_lc]="${if[bn],,}"
}

mapfile -t files_in < <(sudo find "${dirs[@]}" -type f \( -iname "*.avi" -o -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.mpg" -o -iname "*.mpeg" \) 2>&- | grep -Ev "${regex[prune]}")

# Look for files that match the scene naming rules.
for (( i = 0; i < ${#files_in[@]}; i++ )); do
	set_names "${files_in[${i}]}"

# If file name pattern matches YouTube videos, ignore file, and continue
# with the next iteration of the loop.
# * (720p_H.264-AAC).mp4
# * (1080p_30fps_H264-128kbit_AAC).mp4
	if [[ ${if[bn_lc]} =~ ${regex[720p]} || ${if[bn_lc]} =~ ${regex[1080p]} ]]; then
		continue
	fi

# Loop through the rip array, in order to find at least two matches for
# the current $fn.
	count=$(break_name_find "${if[bn_lc]}")

# If directory name contains at least two of the search terms in the
# 'rip' array, continue on.
	if [[ $count -ge 2 ]]; then
		files_out+=("${if[fn]}")
	fi
done

unset -v files_in

for (( i = 0; i < ${#files_out[@]}; i++ )); do
	set_names "${files_out[${i}]}"

	unset -v name_tmp imdb_tmp info

	declare -a name_tmp imdb_tmp
	declare -A info

	mapfile -t name_tmp < <(break_name_parse "${if[bn_lc]}")

	if [[ $mode == 'name' ]]; then
		info[name]="${name_tmp[0]} (${name_tmp[1]})"

		info[id]=$(md5sum -b <<<"${info[name]}")
		info[id]="${info[id]%% *}"
	fi

	if [[ $mode == 'imdb' ]]; then
		if [[ ${name_tmp[1]} != '0000' ]]; then
			mapfile -t imdb_tmp < <(imdb "${name_tmp[0]} (${name_tmp[1]})")
		else
			mapfile -t imdb_tmp < <(imdb "${name_tmp[0]}")
		fi

		info[name]="${imdb_tmp[0]} (${imdb_tmp[1]}): (${imdb_tmp[2]})"

		info[id]="${imdb_tmp[3]}"
	fi

	if [[ -z ${info[id]} ]]; then
		continue
	fi

	if [[ -z ${movie[${info[id]}]} ]]; then
		movie["${info[id]}"]+="${info[name]}\n"
	fi

	movie["${info[id]}"]+="${if[fn]}\n"
done

unset -v name_tmp imdb_tmp info

for key in "${!movie[@]}"; do
	mapfile -t files_out < <(printf '%b' "${movie[${key}]}")

	if [[ ${#files_out[@]} -ge 3 ]]; then
		printf '*** ID: %s\n\n' "${files_out[0]}"

		unset -v files_out[0]

		printf '%s\n' "${files_out[@]}" | sort
		printf '\n'
	fi
done
