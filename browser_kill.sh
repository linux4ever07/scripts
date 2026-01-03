#!/bin/bash

# This is just a simple script to send a signal to 'browser_ram.sh' to
# restart the web browser. If it has stopped responding. This is to
# avoid having to access the hard drive, in case the intention was not
# to quit the browser.

usage () {
	cat <<USAGE

Usage: $(basename "$0") [browser]

	Browsers:

	chromium
	chrome
	brave
	firefox

USAGE

	exit
}

if [[ $# -ne 1 ]]; then
	usage
fi

declare browser
declare -a files
declare -A browsers input output regex

browsers[chromium]=1
browsers[chrome]=1
browsers[brave]=1
browsers[firefox]=1

if [[ -n ${browsers[${1}]} ]]; then
	browser="$1"
else
	usage
fi

regex[bn]="${browser}-[[:digit:]]+-[[:digit:]]+"
regex[ram]="^${regex[bn]}$"

mapfile -t files < <(find '/dev/shm' -mindepth 1 -maxdepth 1 -type d -name "${browser}-*")

for (( i = 0; i < ${#files[@]}; i++ )); do
	input[fn]="${files[${i}]}"
	input[bn]=$(basename "${input[fn]}")

	if [[ ! ${input[bn]} =~ ${regex[ram]} ]]; then
		continue
	fi

	output[restart_fn]="${input[fn]}/kill"

	touch "${output[restart_fn]}"
done
