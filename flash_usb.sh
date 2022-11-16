#!/bin/bash

# This script is meant to flash USB thumbdrives with Linux ISOs.
# Although, any filetype can be given as argument. The script will not
# check if it's an ISO file. The script asks the user to select the
# correct USB device from a menu.

usage () {
	printf '\n%s\n\n' "Usage: $(basename "$0") [image]"
	exit
}

if [[ ! -f $1 ]]; then
	usage
fi

# If the script isn't run with sudo / root privileges, then quit.
if [[ $(whoami) != 'root' ]]; then
	printf '\n%s\n\n' 'You need to be root to run this script!'
	exit
fi

image=$(readlink -f "$1")

declare drive

drive_menu () {
	cd '/dev/disk/by-id'
	mapfile -t devices < <(ls -1 usb* | grep -Ev 'part[0-9]+$')

	select drive_link in "${devices[@]}"; do
		mapfile -d' ' -t info < <(file -b "$drive_link")
		info[-1]="${info[-1]%$'\n'}"

		if [[ -b ${info[-1]} ]]; then
			drive=$(basename "${info[-1]}")
			drive="/dev/${drive}"

			printf '\n%s\n\n' "$drive"

			fdisk -l "$drive"
			printf '\n'
		fi

		break
	done
}

while [[ $REPLY != 'y' ]]; do
	drive_menu

	read -p 'Is this the correct device? [y/n]: '
	printf '\n'
done

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

printf '\n\n%s: %s\n\n' "$drive" 'flashing...'

dd if="$image" of="$drive" bs=1M

if [[ $? -eq 0 ]]; then
	printf '\n%s: %s\n\n' "$drive" 'flash succeeded!'
else
	printf '\n%s: %s\n\n' "$drive" 'flash failed!'
fi

# Synchronize cached writes.
sync
