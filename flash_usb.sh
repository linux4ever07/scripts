#!/bin/bash

# This script is meant to flash USB thumbdrives with Linux ISOs.
# Although, any filetype can be given as argument. The script will not
# check if it's an ISO file. The script asks the user to select the
# correct USB device from a menu.

# Creates a function, called 'usage', which will print usage
# instructions and then quit.
usage () {
	printf '\n%s\n\n' "Usage: $(basename "$0") [image]"
	exit
}

if [[ ! -f $1 ]]; then
	usage
fi

# If the script isn't run with sudo / root privileges, then quit.
if [[ $EUID -ne 0 ]]; then
	printf '\n%s\n\n' 'You need to be root to run this script!'
	exit
fi

declare image device pause_msg exit_status n
declare -A regex

image=$(readlink -f "$1")

regex[part]='-part[0-9]+$'

# Creates a function, called 'get_files', which will print file names in
# the current directory, but only if the glob pattern matches actual
# files. This is to prevent errors for when a pattern has no matches.
get_files () {
	declare glob

	for glob in "$@"; do
		compgen -G "$glob"
	done
}

# Creates a function, called 'device_menu', which will generate a list
# of available USB devices and allow the user to select one of them in a
# menu.
device_menu () {
	declare device_link
	declare -a devices

	cd '/dev/disk/by-id'

	mapfile -t devices < <(get_files "usb-*" | grep -Ev "${regex[part]}")

	if [[ ${#devices[@]} -eq 0 ]]; then
		printf '\n%s\n\n' 'No USB storage devices found!'
		exit
	fi

	printf '\n%s\n\n' 'Choose destination device:'

	select device_link in "${devices[@]}"; do
		device=$(readlink -f "$device_link")

		if [[ -b $device ]]; then
			printf '\n%s\n\n' "$device"

			fdisk -l "$device"
			printf '\n'
		fi

		break
	done
}

while [[ $REPLY != 'y' ]]; do
	device_menu

	read -p 'Is this the correct device? [y/n]: '
	printf '\n'
done

pause_msg="
You are about to flash:
${device}

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

printf '\n\n%s: %s\n\n' "$device" 'flashing...'

dd if="$image" of="$device" bs=1M

exit_status="$?"

# Synchronize cached writes.
sync

if [[ $exit_status -eq 0 ]]; then
	printf '\n%s: %s\n\n' "$device" 'flash succeeded!'
else
	printf '\n%s: %s\n\n' "$device" 'flash failed!'
fi
