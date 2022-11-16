#!/bin/bash

# This script is meant to do low-level formatting of devices, by writing
# 0s to the entire device, reading from /dev/zero.

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
	device=$(readlink -f "$1")

	if [[ ! -b $device ]]; then
		usage
	fi

# If argument is a partition instead of the device itself, strip the
# partition number from the path.
	if [[ $device =~ $regex_part ]]; then
		device="${BASH_REMATCH[1]}"
	fi

# List information about the device using 'fdisk'.
	printf '\n'
	fdisk -l "$device"
	printf '\n'

	pause_msg="
You are about to do a low-level format of:
${device}

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

	printf '\n\n%s: %s\n\n' "$device" 'formatting...'

	dd if='/dev/zero' of="$device" bs=1M

	if [[ $? -eq 0 ]]; then
		printf '\n%s: %s\n\n' "$device" 'format succeeded!'
	else
		printf '\n%s: %s\n\n' "$device" 'format failed!'
	fi

	shift
done

# Synchronize cached writes.
sync
