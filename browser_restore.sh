#!/bin/bash

# This script restores the web browser config / cache, after an
# unclean shutdown. This script is related to 'browser_ram.sh'.

# The script has 2 modes, 'ram' and 'backup'.

# In 'ram' mode, the script restores config and cache from RAM to $HOME.

# In 'backup' mode, the script restores config from the latest backup
# archive found in $HOME.

usage () {
	cat <<USAGE

Usage: $(basename "$0") [browser] [mode]

	Browsers:

	chromium
	chrome
	brave
	firefox

	Modes:

	ram
	backup

USAGE

	exit
}

if [[ $# -ne 2 ]]; then
	usage
fi

declare browser mode date ram_date bak_date key
declare -a files
declare -A browsers browsers_info input output regex

browsers[chromium]=1
browsers[chrome]=1
browsers[brave]=1
browsers[firefox]=1

browsers_info[chromium,cfg]="${HOME}/.config/chromium"
browsers_info[chromium,cache]="${HOME}/.cache/chromium"

browsers_info[chrome,cfg]="${HOME}/.config/google-chrome"
browsers_info[chrome,cache]="${HOME}/.cache/google-chrome"

browsers_info[brave,cfg]="${HOME}/.config/BraveSoftware/Brave-Browser"
browsers_info[brave,cache]="${HOME}/.cache/BraveSoftware/Brave-Browser"

browsers_info[firefox,cfg]="${HOME}/.mozilla"
browsers_info[firefox,cache]="${HOME}/.cache/mozilla"

if [[ -n ${browsers[${1}]} ]]; then
	browser="$1"
else
	usage
fi

shift

case "$1" in
	'ram')
		mode='ram'
	;;
	'backup')
		mode='backup'
	;;
	*)
		usage
	;;
esac

ram_date=0
bak_date=0

input[og_cfg]="${browsers_info[${browser},cfg]}"
input[og_cache]="${browsers_info[${browser},cache]}"

regex[bn]="${browser}-[[:digit:]]+-[[:digit:]]+"
regex[ram]="^${regex[bn]}$"
regex[bak]="^${regex[bn]}\.tar$"

mapfile -t files < <(find '/dev/shm' -mindepth 1 -maxdepth 1 -type d -name "${browser}-*")

for (( i = 0; i < ${#files[@]}; i++ )); do
	input[fn]="${files[${i}]}"
	input[bn]=$(basename "${input[fn]}")

	if [[ ! ${input[bn]} =~ ${regex[ram]} ]]; then
		continue
	fi

	date=$(stat -c '%Y' "${input[fn]}")

	if [[ $date -gt $ram_date ]]; then
		input[ram_fn]="${input[fn]}"
		ram_date="$date"
	fi
done

mapfile -t files < <(find "$HOME" -mindepth 1 -maxdepth 1 -type f -name "${browser}-*.tar")

for (( i = 0; i < ${#files[@]}; i++ )); do
	input[fn]="${files[${i}]}"
	input[bn]=$(basename "${input[fn]}")

	if [[ ! ${input[bn]} =~ ${regex[bak]} ]]; then
		continue
	fi

	date=$(stat -c '%Y' "${input[fn]}")

	if [[ $date -gt $bak_date ]]; then
		input[bak_fn]="${input[fn]}"
		bak_date="$date"
	fi
done

case "$mode" in
	'ram')
		if [[ -z ${input[ram_fn]} ]]; then
			exit
		fi
	;;
	'backup')
		if [[ -z ${input[bak_fn]} ]]; then
			exit
		fi
	;;
esac

for key in "${input[og_cfg]}" "${input[og_cache]}"; do
	input[dn]="$key"

	if [[ -L ${input[dn]} ]]; then
		rm "${input[dn]}" || exit
	fi

	if [[ -d ${input[dn]} ]]; then
		rm -r "${input[dn]}" || exit
	fi

	mkdir -p "${input[dn]}" || exit
done

sync

case "$mode" in
	'ram')
		output[ram_cfg]="${input[ram_fn]}/config"
		output[ram_cache]="${input[ram_fn]}/cache"

		mapfile -t files < <(compgen -G "${output[ram_cfg]}/*")

		if [[ ${#files[@]} -gt 0 ]]; then
			cp -rp "${files[@]}" "${input[og_cfg]}" || exit
		fi

		mapfile -t files < <(compgen -G "${output[ram_cache]}/*")

		if [[ ${#files[@]} -gt 0 ]]; then
			cp -rp "${files[@]}" "${input[og_cache]}" || exit
		fi

		sync

		rm -r "${input[ram_fn]}" || exit
	;;
	'backup')
		cd "${input[og_cfg]}" || exit
		tar -xf "${input[bak_fn]}" || exit

		sync
	;;
esac
