#!/bin/bash
# This script parses a BitTorrent tracker list text file, sorts, removes
# duplicates, checks online status of each URL, and prints the list to
# STDOUT in the correct format.

# Only the trackers that are still online will be printed. This is
# useful to clean up old lists of public trackers that can be found
# online, as an example. Though, it might be a good idea to run the
# script a couple of times, waiting a few hours or days inbetween, since
# a tracker could be only temporarily offline.

# Any tracker URL using protocols besides HTTP, HTTPS and UDP will be
# ignored / skipped by this script, when checking online status.

# The second argument to the script (-nocheck), is optional. If used,
# the online status of trackers will not be checked, but the list will
# only get sorted and rid of duplicates.

# If you want to save the list in a text file, you can just do a
# redirection like so:

# tracker_list.sh 'trackers.txt' | tee 'trackers_checked.txt'

usage () {
	printf '%s\n\n' "Usage: $(basename "$0") [tracker txt] [-nocheck]"
	exit
}

if [[ -z $1 || ! -f $1 ]]; then
	usage
elif [[ ! -z $2 && $2 != '-nocheck' ]]; then
	usage
fi

nocheck=0

if [[ $2 == '-nocheck' ]]; then
	nocheck=1
fi

if=$(readlink -f "$1")
switch=0

regex1='^([[:alpha:]]+)://'
regex2=':([0-9]+)'
regex3='/.*$'
regex4='/announce(\.[[:alpha:]]{1,4}){0,1}$'
regex5='/$'

declare -a trackers

mapfile -t lines < <(sort --unique <"$if")

for (( i = 0; i < ${#lines[@]}; i++ )); do
	line=$(tr -d '[:space:]' <<<"${lines[${i}]}")
	switch=0

	if [[ ! -z $line ]]; then
		for (( j = 0; j < ${#trackers[@]}; j++ )); do
			line_tmp=$(sed -E -e "s_${regex4}__" -e "s_${regex5}__" <<<"$line")
			grep --quiet "$line_tmp" <<<"${trackers[${j}]}"

			if [[ $? -eq 0 ]]; then
				switch=1

				array_l="${#trackers[${j}]}"
				line_l="${#line}"

				if [[ $line_l > $array_l && $line =~ $regex4 ]]; then
					trackers[${j}]="$line"
				fi
			fi
		done

		if [[ $switch -eq 0 ]]; then
			trackers+=("$line")
		fi
	fi
done

declare -A md5h

for (( i = 0; i < ${#trackers[@]}; i++ )); do
	tracker=$(tr -d '[:space:]' <<<"${trackers[${i}]}")
	md5=$(md5sum <<<"$tracker")

	if [[ ${md5h[${md5}]} -eq 1 ]]; then
		continue
	else
		md5h[${md5}]=1
	fi

	if [[ $nocheck -eq 1 ]]; then
		printf '%s\n\n' "$tracker"

		continue
	fi

	address=$(sed -E -e "s_${regex1}__" -e "s_${regex2}__" -e "s_${regex3}__" <<<"$tracker")
	protocol=$(grep -Eo "$regex1" <<<"$tracker" | sed -E "s_${regex1}_\1_" | tr '[:upper:]' '[:lower:]')
	port=$(grep -Eo "$regex2" <<<"$tracker" | sed -E "s_${regex2}_\1_")

	case $protocol in
		http*)
			curl --retry 10 --retry-delay 10 --connect-timeout 10 --silent --output /dev/null "$tracker"
		;;
		udp)
			for n in {1..10}; do
				timeout 10 nc --udp -z "$address" "$port" &> /dev/null
			done
		;;
		*)
			continue
		;;
	esac

	if [[ $? -ne 0 ]]; then
		ping -c 10 -W 10 "$address" &> /dev/null

		if [[ $? -eq 0 ]]; then
			printf '%s\n\n' "$tracker"
		fi
	elif [[ $? -eq 0 ]]; then
		printf '%s\n\n' "$tracker"
	fi
done
