#!/bin/bash

# This script is meant to do low-level formatting of devices, by writing
# 0s to the entire drive, reading from /dev/zero.

usage () {
	printf '\n%s\n\n' "Usage: $(basename "$0") [devices...]"
	exit
}

if [[ $# -eq 0 ]]; then
	usage
fi

# If the script isn't run with sudo / root privileges, then quit.
if [[ $(whoami) != 'root' ]]; then
	printf '\n%s\n\n' 'You need to be root to run this script!'
	exit
fi

regex_part="^(.*)[0-9]+$"

while [[ $# -gt 0 ]]; do
	drive=$(readlink -f "$1")

	if [[ ! -b $drive ]]; then
		usage
	fi

# If argument is a partition instead of the device itself, strip the
# partition number from the path.
	if [[ $drive =~ $regex_part ]]; then
		drive="${BASH_REMATCH[1]}"
	fi

# List information about the device using 'fdisk'.
	printf '\n'
	fdisk -l "$drive"
	printf '\n'

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

	printf '\n\n%s: %s\n\n' "$drive" 'formatting...'

	dd if='/dev/zero' of="$drive" bs=1M

	if [[ $? -eq 0 ]]; then
		printf '\n%s: %s\n\n' "$drive" 'format succeeded!'
	else
		printf '\n%s: %s\n\n' "$drive" 'format failed!'
	fi

	shift
done

# Synchronize cached writes.
sync
