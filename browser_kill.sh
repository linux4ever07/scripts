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

declare browser fn bn restart_fn
declare -a files
declare -A browsers regex

browsers[chromium]=1
browsers[chrome]=1
browsers[brave]=1
browsers[firefox]=1

if [[ -n ${browsers[${1}]} ]]; then
	browser="$1"
else
	usage
fi

regex[bn]="${browser}-[0-9]+-[0-9]+"
regex[ram]="^${regex[bn]}$"

mapfile -t files < <(find '/dev/shm' -mindepth 1 -maxdepth 1 -type d -name "${browser}-*")

for (( i = 0; i < ${#files[@]}; i++ )); do
	fn="${files[${i}]}"
	bn=$(basename "$fn")

	if [[ ! $bn =~ ${regex[ram]} ]]; then
		continue
	fi

	restart_fn="${fn}/kill"

	touch "$restart_fn"
done
