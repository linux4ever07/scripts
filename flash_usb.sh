#!/bin/bash

# This script is meant to flash USB thumbdrives with Linux ISOs.
# Although, any filetype can be given as argument. The script will not
# check if it's an ISO file.

usage () {
	printf '\n%s\n\n' "Usage: $(basename "$0") [device] [image]"
	exit
}

if [[ ! -b $1 || ! -f $2 ]]; then
	usage
fi

# If the script isn't run with sudo / root privileges, then quit.
if [[ $(whoami) != 'root' ]]; then
	printf '\n%s\n\n' 'You need to be root to run this script!'
	exit
fi

regex_part="^(.*)[0-9]+$"

drive=$(readlink -f "$1")
image=$(readlink -f "$2")

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
You are about to flash:
${drive}

With:
${image}

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

printf '\n\n%s: %s\n' "$drive" 'flashing...'

dd if="$image" of="$drive" bs=1M

if [[ $? -eq 0 ]]; then
	printf '\n%s: %s\n\n' "$drive" 'flash succeeded!'
else
	printf '\n%s: %s\n\n' "$drive" 'flash failed!'
fi

# Synchronize cached writes.
sync
