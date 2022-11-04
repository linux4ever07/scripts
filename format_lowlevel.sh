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

pause_msg="
You are about to do a low-level format of:
${drive}

Are you sure? [y/n]: "

while [[ -n $@ ]]; do
	drive=$(readlink -f "$1")

	if [[ ! -b $drive ]]; then
		usage
	fi

	read -p "$pause_msg"

	if [[ $REPLY != 'y' ]]; then
		exit
	fi

	printf '\n'

	for n in {1..10}; do
		printf "%s..." "$n"
		sleep 1
	done

	printf '\n\nFormatting...\n'

	dd if='/dev/zero' of="${drive}" bs=1M

	if [[ $? -eq 0 ]]
		printf '\n%s\n\n' 'Format succeeded!'
	else
		printf '\n%s\n\n' 'Format failed!'
	fi

	shift
done
