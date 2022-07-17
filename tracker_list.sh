#!/bin/bash
# This script parses a BitTorrent tracker list text file, sorts, removes
# duplicates, checks online status of each URL, and echoes the list to
# STDOUT in the correct format.

usage () {
	bname=$(basename "$0")
	printf '%s\n' "Usage: ${bname} [tracker txt]"
	exit
}

if [[ -z $1 || ! -f $1 ]]; then
	usage
fi

declare -a trackers

txt="$1"
txt_tmp="/dev/shm/trackers-${RANDOM}.txt"
line_n=0
n=0
switch=0
elements=0

sort --unique <"$txt" > "$txt_tmp"
txt_n=$(wc --lines <"$txt_tmp")

cat "$txt_tmp" | while read line; do
	switch=0
	let line_n++

	if [[ $line ]]; then
		elements=${#trackers[@]}

		for (( i = 0; i < $elements; i++ )); do
			line_tmp=$(sed -e 's_/$__' -e 's_/announce__' <<<"$line")
			grep --quiet "$line_tmp" <<<"${trackers[${i}]}"

			if [[ $? -eq 0 ]]; then
				switch=1

				array_l=$(wc --chars <<<"${trackers[${i}]}")
				line_l=$(wc --chars <<<"$line")

				if [[ $line_l > $array_l && $line =~ /announce$ ]]; then
					trackers[${i}]="$line"
				fi
			fi
		done

		if [[ $switch -eq 0 ]]; then
			trackers[${n}]="$line"
			let n++
		fi
	fi

	if [[ $line_n -eq $txt_n ]]; then
		elements=${#trackers[@]}

		declare -A md5h

		for (( i = 0; i < $elements; i++ )); do
			md5=$(tr -d '[:space:]' <<<"${trackers[${i}]}" | md5sum -)

			if [[ ${md5h[${md5}]} -eq 1 ]]; then
				continue
			else
				md5h[${md5}]=1
			fi

			curl --retry 8 --silent --output /dev/null "${trackers[${i}]}"

			if [[ $? -ne 0 ]]; then
				address=$(sed -e 's_^.*//__' -e 's_:[0-9]*__' -e 's_/.*$__' <<<"${trackers[${i}]}")
				ping -c 10 "$address" &> /dev/null

				if [[ $? -eq 0 ]]; then
					printf '%s\n' "${trackers[${i}]}"
				fi

			elif [[ $? -eq 0 ]]; then
				printf '%s\n' "${trackers[${i}]}"
			fi
		done
	fi
done

rm "$txt_tmp"
