#!/bin/bash

# This script is meant to do low-level formatting of devices, by writing
# 0s to the entire drive, reading from /dev/zero.

usage () {
	printf '\n%s\n\n' "Usage: $(basename "$0") [devices...]"
	exit
}

if [[ -z $1 ]]; then
	usage
fi

# If the script isn't run with sudo / root privileges, then quit.
if [[ $(whoami) != 'root' ]]; then
	printf '\n%s\n\n' 'You need to be root to run this script!'
	exit
fi

while [[ $# -gt 0 ]]; do
	drive=$(readlink -f "$1")

	if [[ ! -b $drive ]]; then
		usage
	fi

	pause_msg="
You are about to do a low-level format of:
${drive}

Are you sure? [y/n]: "

	read -p "$pause_msg"

	if [[ $REPLY != 'y' ]]; then
		exit
	fi

	printf '\n'

	for n in {1..10}; do
		printf "%s..." "$n"
		sleep 1
	done

	printf '\n\n%s: %s\n' "$drive" 'formatting...'

	dd if='/dev/zero' of="${drive}" bs=1M

	if [[ $? -eq 0 ]]; then
		printf '\n%s: %s\n\n' "$drive" 'format succeeded!'
	else
		printf '\n%s: %s\n\n' "$drive" 'format failed!'
	fi

	shift
done
