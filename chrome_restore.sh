#!/bin/bash

# This script restores the Google Chrome config / cache, after an
# unclean shutdown. This script is related to 'chrome_ram.sh'.

# The script has 2 modes, 'ram' and 'backup'.

# In 'ram' mode, the script restores config and cache from RAM to $HOME.

# In 'backup' mode, the script restores config from the latest backup
# archive found in $HOME.

usage () {
	printf '\n%s\n\n' "Usage: $(basename "$0") [ram|backup]"
	exit
}

if [[ $# -ne 1 ]]; then
	usage
fi

declare mode

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

declare ram_fn ram_date bak_fn bak_date
declare -a files
declare -A regex

ram_date=0
bak_date=0

cfg="${HOME}/.config/google-chrome"
cache="${HOME}/.cache/google-chrome"

regex[bn]='google-chrome-[0-9]+-[0-9]+'
regex[ram]="^${regex[bn]}$"
regex[bak]="^${regex[bn]}\.tar$"

mapfile -t files < <(find '/dev/shm' -mindepth 1 -maxdepth 1 -type d -name "google-chrome-*")

for (( i = 0; i < ${#files[@]}; i++ )); do
	fn="${files[${i}]}"
	bn=$(basename "$fn")

	if [[ ! $bn =~ ${regex[ram]} ]]; then
		continue
	fi

	date=$(stat -c '%Y' "$fn")

	if [[ $date -gt $ram_date ]]; then
		ram_fn="$fn"
		ram_date="$date"
	fi
done

mapfile -t files < <(find "$HOME" -mindepth 1 -maxdepth 1 -type f -name "google-chrome-*.tar")

for (( i = 0; i < ${#files[@]}; i++ )); do
	fn="${files[${i}]}"
	bn=$(basename "$fn")

	if [[ ! $bn =~ ${regex[bak]} ]]; then
		continue
	fi

	date=$(stat -c '%Y' "$fn")

	if [[ $date -gt $bak_date ]]; then
		bak_fn="$fn"
		bak_date="$date"
	fi
done

case "$mode" in
	'ram')
		if [[ -z $ram_fn ]]; then
			exit
		fi
	;;
	'backup')
		if [[ -z $bak_fn ]]; then
			exit
		fi
	;;
esac

for dn in "$cfg" "$cache"; do
	if [[ -L "$dn" ]]; then
		rm "$dn" || exit
	fi

	if [[ -d "$dn" ]]; then
		rm -r "$dn" || exit
	fi

	mkdir -p "$dn" || exit
done

sync

case "$mode" in
	'ram')
		ram_cfg="${ram_fn}/config"
		ram_cache="${ram_fn}/cache"

		mapfile -t files < <(compgen -G "${ram_cfg}/*")

		if [[ ${#files[@]} -gt 0 ]]; then
			cp -rp "${files[@]}" "$cfg" || exit
		fi

		mapfile -t files < <(compgen -G "${ram_cache}/*")

		if [[ ${#files[@]} -gt 0 ]]; then
			cp -rp "${files[@]}" "$cache" || exit
		fi

		sync

		rm -r "$ram_fn" || exit
	;;
	'backup')
		cd "$cfg" || exit
		tar -xf "$bak_fn" || exit

		sync
	;;
esac
