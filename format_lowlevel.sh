#!/bin/bash

# This script is meant to do low-level formatting of devices, by writing
# 0s to the entire device, reading from /dev/zero.

# Creates a function, called 'usage', which will print usage
# instructions and then quit.
usage () {
	printf '\n%s\n\n' "Usage: $(basename "$0") [devices...]"
	exit
}

if [[ $# -eq 0 ]]; then
	usage
fi

# If the script isn't run with sudo / root privileges, then quit.
if [[ $EUID -ne 0 ]]; then
	printf '\n%s\n\n' 'You need to be root to run this script!'
	exit
fi

declare device pause_msg exit_status n
declare -a types args
declare -A regex

types=('quick' 'full')

regex[part]='^(.*)[0-9]+$'

while [[ $# -gt 0 ]]; do
	device=$(readlink -f "$1")

	if [[ ! -b $device ]]; then
		usage
	fi

	unset -v type
	declare type

# If argument is a partition instead of the device itself, strip the
# partition number from the path.
	if [[ $device =~ ${regex[part]} ]]; then
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

# Ask the user whether they want to do a quick or full format.
	printf '\n%s\n\n' 'Do you want to do a quick or full format?'

	until [[ -n $type ]]; do
		select type in "${types[@]}"; do
			break
		done
	done

	printf '\n'

	for n in {1..10}; do
		printf "%s..." "$n"
		sleep 1
	done

	printf '\n\n%s: %s\n\n' "$device" 'formatting...'

# Depending on whether we're doing a quick or full format, adjust the
# arguments to 'dd'.
	args=(dd if=\""/dev/zero"\" of=\""${device}"\" bs=\""1M"\")

	if [[ $type == 'quick' ]]; then
		args+=(count=\""100"\")
	fi

# Run 'dd'.
	eval "${args[@]}"

	exit_status="$?"

# Synchronize cached writes.
	sync

	if [[ $exit_status -eq 0 ]]; then
		printf '\n%s: %s\n\n' "$device" 'format succeeded!'
	else
		printf '\n%s: %s\n\n' "$device" 'format failed!'
	fi

	shift
done
