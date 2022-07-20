#!/bin/bash
# This script parses a BitTorrent tracker list text file, sorts, removes
# duplicates, checks online status of each URL, and prints the list to
# STDOUT in the correct format.

usage () {
	printf '%s\n\n' "Usage: $(basename "$0") [tracker txt]"
	exit
}

if [[ -z $1 || ! -f $1 ]]; then
	usage
fi

if=$(readlink -f "$1")
switch=0

declare -a trackers

mapfile -t lines < <(sort --unique <"$if")

for (( i = 0; i < ${#lines[@]}; i++ )); do
	line="${lines[${i}]}"
	switch=0

	if [[ ! -z $line ]]; then
		for (( j = 0; j < ${#trackers[@]}; j++ )); do
			line_tmp=$(sed -e 's_/$__' -e 's_/announce__' <<<"$line")
			grep --quiet "$line_tmp" <<<"${trackers[${j}]}"

			if [[ $? -eq 0 ]]; then
				switch=1

				array_l="${#trackers[${j}]}"
				line_l="${#line}"

				if [[ $line_l > $array_l && $line =~ /announce$ ]]; then
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
	tracker="${trackers[${i}]}"
	md5=$(tr -d '[:space:]' <<<"$tracker" | md5sum -)

	if [[ ${md5h[${md5}]} -eq 1 ]]; then
		continue
	else
		md5h[${md5}]=1
	fi

	curl --retry 8 --silent --output /dev/null "$tracker"

	if [[ $? -ne 0 ]]; then
		address=$(sed -e 's_^.*//__' -e 's_:[0-9]*__' -e 's_/.*$__' <<<"$tracker")
		ping -c 10 "$address" &> /dev/null

		if [[ $? -eq 0 ]]; then
			printf '%s\n\n' "$tracker"
		fi
	elif [[ $? -eq 0 ]]; then
		printf '%s\n\n' "$tracker"
	fi
done
