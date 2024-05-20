#!/bin/bash

# This script parses BitTorrent tracker list text files, sorts, removes
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

declare nocheck
declare -a files

nocheck=0

# Creates a function, called 'usage', which will print usage
# instructions and then quit.
usage () {
	printf '\n%s\n\n' "Usage: $(basename "$0") [tracker txt] [-nocheck]"
	exit
}

# The loop below handles the arguments to the script.
while [[ $# -gt 0 ]]; do
	case "$1" in
		'-nocheck')
			nocheck=1

			shift
		;;
		*)
			if [[ -f $1 ]]; then
				files+=("$(readlink -f "$1")")
			else
				usage
			fi

			shift
		;;
	esac
done

if [[ ${#files[@]} -eq 0 ]]; then
	usage
fi

declare line end_l end_tmp_l switch n
declare protocol address end port tracker
declare protocol_tmp address_tmp end_tmp port_tmp
declare -a lines_out protocols addresses ends ports
declare -A regex

regex[url]='^([[:alpha:]]+):\/\/([^:\/]+)(.*)$'
regex[end]='^(.*):([0-9]+)(.*)$'

# Creates a function, called 'get_lines', which reads the files given as
# arguments to the script into memory.
get_lines () {
	declare fn
	declare -a lines_in

	for (( z = 0; z < ${#files[@]}; z++ )); do
		fn="${files[${z}]}"

		declare -a lines

		mapfile -t lines < <(tr -d '\r' <"$fn" | tr '[:upper:]' '[:lower:]' | sed -E 's/[[:blank:]]+/\n/g')
		lines_in+=("${lines[@]}")

		unset -v lines
	done

	mapfile -t lines_out < <(printf '%s\n' "${lines_in[@]}" | sort -u)
}

get_lines

for (( i = 0; i < ${#lines_out[@]}; i++ )); do
	line="${lines_out[${i}]}"

	switch=0

# Deletes the line from memory, since we already have a temporary
# duplicate.
	lines_out["${i}"]=''

# Checks if the current line matches the URL regex, and if not continue
# the next iteration of the loop.
	if [[ ! $line =~ ${regex[url]} ]]; then
		continue
	fi

	protocol="${BASH_REMATCH[1]}"
	address="${BASH_REMATCH[2]}"
	end="${BASH_REMATCH[3]}"

# If there's no port number in the URL, use port 80. Otherwise, just use
# the one in the URL.
	port=80

	if [[ $end =~ ${regex[end]} ]]; then
		end="${BASH_REMATCH[1]}${BASH_REMATCH[3]}"
		port="${BASH_REMATCH[2]}"
	fi

# Compares the tracker URL with ones that have already been added to the
# list.
	for (( j = 0; j < ${#addresses[@]}; j++ )); do
		protocol_tmp="${protocols[${j}]}"
		address_tmp="${addresses[${j}]}"
		end_tmp="${ends[${j}]}"
		port_tmp="${ports[${j}]}"

		if [[ $protocol != "$protocol_tmp" ]]; then
			continue
		fi

		if [[ $port != "$port_tmp" ]]; then
			continue
		fi

# If the address matches, then check which has the longest URL ending.
# A new element will not be created in the list, but the longest match
# is used.
		if [[ $address == "$address_tmp" ]]; then
			switch=1

			end_l="${#end}"
			end_tmp_l="${#end_tmp}"

			if [[ $end_l > $end_tmp_l ]]; then
				ends["${j}"]="$end"
			fi
		fi
	done

# If this URL is unique, add it to the different lists.
	if [[ $switch -eq 0 ]]; then
		protocols+=("$protocol")
		addresses+=("$address")
		ends+=("$end")
		ports+=("$port")
	fi
done

# The loop below goes through each URL, and checks online status. If the
# URL is online, print it. If '-nocheck' was used, just print the URL
# and keep iterating the loop.
for (( i = 0; i < ${#addresses[@]}; i++ )); do
	protocol="${protocols[${i}]}"
	address="${addresses[${i}]}"
	end="${ends[${i}]}"
	port="${ports[${i}]}"

	tracker="${protocol}://${address}:${port}${end}"

	if [[ $nocheck -eq 1 ]]; then
		printf '%s\n\n' "$tracker"

		continue
	fi

	case $protocol in
		http*)
			curl --retry 10 --retry-delay 10 --connect-timeout 10 --silent --output /dev/null "$tracker"
		;;
		udp)
			for n in {1..10}; do
				timeout 10 nc --udp -z "$address" "$port" 1>&- 2>&-
			done
		;;
		*)
			continue
		;;
	esac

	if [[ $? -ne 0 ]]; then
		ping -c 10 -W 10 "$address" &>/dev/null

		if [[ $? -eq 0 ]]; then
			printf '%s\n\n' "$tracker"
		fi
	elif [[ $? -eq 0 ]]; then
		printf '%s\n\n' "$tracker"
	fi
done
