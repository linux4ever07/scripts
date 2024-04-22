#!/bin/bash

# This script is meant to sort out good video game ROMs from full sets.
# It will prefer US ROMs, but use another region if that's not
# available.

# According to GoodTools naming practices, good (verified) ROM dumps,
# have the '[!]' tag.

# For best results, run your ROM collection through GoodTools before
# using this script, if it has not been already. That will properly
# format all the ROM filenames, so the tags will be recognized.

# The region priority order is: U, UK, A, W, E, J.

# U = US
# UK = United Kingdom
# A = Australia
# W = World
# E = Europe
# J = Japan

# Special tags for Genesis:

# 4 = US
# 8 = PAL
# 1 = Japan
# 5 = NTSC

# Creates a function, called 'usage', which will print usage
# instructions and then quit.
usage () {
	printf '\n%s\n\n' "Usage: $(basename "$0") [ROM directory]"
	exit
}

if [[ ! -d $1 ]]; then
	usage
fi

declare if_dn of_dn session title target
declare -a global_vars priority files
declare -A regex titles

session="${RANDOM}-${RANDOM}"

if_dn=$(readlink -f "$1")
of_dn="sorted-${session}"

regex[blank]='^[[:blank:]]*(.*)[[:blank:]]*$'
regex[ext]='\.([^.]*)$'
regex[1]="\(([A-Z]{1,3}|[0-9]{1})\).*${regex[ext]}"
regex[2]="^.*(\[\!\]).*${regex[ext]}"

global_vars=('fn' 'bn' 'region' 'region_n')
priority=('^U$' 'U' '^4$' '^UK$' '^A$' 'A' '^W$' '^E$' 'E' '^8$' '^J$' 'J' '^1$' '^5$')

cd "$if_dn"
mkdir "$of_dn"

mapfile -t files < <(find "$if_dn" -maxdepth 1 -type f 2>&-)

set_target () {
	set_vars () {
		titles["${title}"]="$region_n"
	}

	for (( j = 0; j < ${#priority[@]}; j++ )); do
		target="${priority[${j}]}"

		if [[ ! $region =~ $target ]]; then
			continue
		fi

		region_n="$j"

		if [[ ${titles[${title}]} != 'undef' ]]; then
			if [[ $region_n -lt ${titles[${title}]} ]]; then
				set_vars
			fi
		else
			set_vars
		fi

		break
	done
}

loop_intro () {
	fn="${files[${i}]}"
	bn=$(basename "$fn")

	if [[ ! $bn =~ ${regex[1]} ]]; then
		return
	fi

	region="${BASH_REMATCH[1]}"

	if [[ ! $bn =~ ${regex[2]} ]]; then
		unset -v region
	fi
}

get_games () {
	for (( i = 0; i < ${#files[@]}; i++ )); do
		fn="${files[${i}]}"
		bn=$(basename "$fn")

		if [[ ! $bn =~ ${regex[1]} ]]; then
			continue
		fi

		title=$(sed -E "s/${regex[1]}//" <<<"$bn")

		if [[ -n $title ]]; then
			titles["${title}"]='undef'
		fi
	done
}

get_games

# Gets the verified ROMs.
for title in "${!titles[@]}"; do
	mapfile -t files < <(find "$if_dn" -maxdepth 1 -type f -name "${title}*" 2>&-)

	for (( i = 0; i < ${#files[@]}; i++ )); do
		declare "${global_vars[@]}"

		loop_intro

		if [[ -z $region ]]; then
			unset -v "${global_vars[@]}"
			continue
		fi

		set_target

		unset -v "${global_vars[@]}"
	done

	for (( i = 0; i < ${#files[@]}; i++ )); do
		declare "${global_vars[@]}"

		loop_intro

		if [[ -z $region ]]; then
			unset -v "${global_vars[@]}"
			continue
		fi

		for (( j = 0; j < ${#priority[@]}; j++ )); do
			target="${priority[${j}]}"

			if [[ ! $region =~ $target ]]; then
				continue
			fi

			region_n="$j"
			break
		done

		if [[ $region_n == "${titles[${title}]}" ]]; then
			printf '%s\n' "$bn"
			mv -n "$bn" "$of_dn" || exit
		fi

		unset -v "${global_vars[@]}"
	done
done
