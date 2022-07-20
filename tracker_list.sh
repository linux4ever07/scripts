#!/bin/bash
# This script parses a BitTorrent tracker list text file, sorts, removes
# duplicates, checks online status of each URL, and echoes the list to
# STDOUT in the correct format.

usage () {
	bname=$(basename "$0")
	printf '%s\n\n' "Usage: ${bname} [tracker txt]"
	exit
}

if [[ -z $1 || ! -f $1 ]]; then
	usage
fi

if=$(readlink -f "$1")
switch=0

declare -a trackers

mapfile -t lines < <(sort --unique <"$if")
end=$(( ${#lines[@]} - 1 ))

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
			trackers[${j}]="$line"
		fi
	fi

	if [[ $i -eq $end ]]; then
		declare -A md5h

		for (( j = 0; j < ${#trackers[@]}; j++ )); do
			md5=$(tr -d '[:space:]' <<<"${trackers[${j}]}" | md5sum -)

			if [[ ${md5h[${md5}]} -eq 1 ]]; then
				continue
			else
				md5h[${md5}]=1
			fi

			curl --retry 8 --silent --output /dev/null "${trackers[${j}]}"

			if [[ $? -ne 0 ]]; then
				address=$(sed -e 's_^.*//__' -e 's_:[0-9]*__' -e 's_/.*$__' <<<"${trackers[${j}]}")
				ping -c 10 "$address" &> /dev/null

				if [[ $? -eq 0 ]]; then
					printf '%s\n' "${trackers[${j}]}"
				fi

			elif [[ $? -eq 0 ]]; then
				printf '%s\n' "${trackers[${j}]}"
			fi
		done
	fi
done
