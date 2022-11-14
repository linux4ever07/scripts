#!/bin/bash

# This is a script that runs the Google Chrome config / cache from
# /dev/shm (RAM). Running the whole application in RAM like this makes
# it more responsive. However, it's not a good idea to do this unless
# you have lots of RAM.

# The script has 2 modes, 'normal' and 'clean'.

# In 'normal' mode, the script copies over config and cache from $HOME
# to /dev/shm, and later restores it after the Chrome process quits.
# Also, the script makes a backup TAR file of the /dev/shm config
# directory every 30 minutes, in case of a power outage or OS crash.
# That backup is saved to $HOME. It's not automatically removed when
# the script quits, so you have to remove it manually between each
# session.

# In 'clean' mode, it runs a clean instance of Chrome with a fresh
# config and cache. Whatever changes are made to that config will be
# discarded, and when the Chrome process quits, the original config and
# cache are restored.

# The script also checks the amount of free RAM every 10 seconds, to
# make sure it's not less than 1GB ($limit). If it's less, then Chrome
# will be killed and the config / cache directories restored to the hard
# drive. This is to make sure those directories don't get corrupted
# when there's not enough free space in /dev/shm to write files.

usage () {
	printf '\n%s\n\n' "Usage: $(basename "$0") [normal|clean]"
	exit
}

if [[ $# -ne 1 ]]; then
	usage
fi

declare mode

case "$1" in
	'normal')
		mode='normal'
	;;
	'clean')
		mode='clean'
	;;
	*)
		usage
	;;
esac

mapfile -t is_chrome < <(ps -C chrome -o pid | tail -n +2 | tr -d '[:blank:]')

if [[ ${#is_chrome[@]} -gt 0 ]]; then
	printf '\n%s\n\n' 'Chrome is already running!'
	exit
fi

session="${RANDOM}-${RANDOM}"
limit=1000000

og_cfg="${HOME}/.config/google-chrome"
og_cache="${HOME}/.cache/google-chrome"

bak_cfg="${og_cfg}-${session}"
bak_cache="${og_cache}-${session}"

shm_dn="/dev/shm/google-chrome-${session}"
shm_cfg="${shm_dn}/config"
shm_cache="${shm_dn}/cache"

tar_fn="${HOME}/google-chrome-${session}.tar"

cwd="$PWD"

restore_chrome () {
	printf '\n%s\n\n' 'Restoring Chrome config / cache...'

	rm "$og_cfg" "$og_cache" || exit

	if [[ $mode == 'normal' ]]; then
		mkdir -p "$og_cfg" "$og_cache" || exit
		cp -rp "$shm_cfg"/* "$og_cfg" || exit
		cp -rp "$shm_cache"/* "$og_cache" || exit
	fi

	if [[ $mode == 'clean' ]]; then
		mv "$bak_cfg" "$og_cfg" || exit
		mv "$bak_cache" "$og_cache" || exit
	fi

	rm -rf "$shm_dn"

	sync
	cd "$cwd"
}

kill_chrome () {
	kill -9 "$pid"

	restore_chrome

	exit
}

mkdir -p "$og_cfg" "$og_cache" || exit

mv "$og_cfg" "$bak_cfg" || exit
mv "$og_cache" "$bak_cache" || exit

mkdir -p "$shm_cfg" "$shm_cache" || exit

ln -s "$shm_cfg" "$og_cfg" || exit
ln -s "$shm_cache" "$og_cache" || exit

if [[ $mode == 'normal' ]]; then
	printf '\n%s\n\n' 'Copying Chrome config / cache to /dev/shm...'

	cp -rp "$bak_cfg"/* "$shm_cfg" || exit
	cp -rp "$bak_cache"/* "$shm_cache" || exit
	rm -rf "$bak_cache" || exit
fi

printf '\n%s\n\n' 'Starting Chrome...'

google-chrome 1>&- 2>&- &
pid="$!"

if [[ $mode == 'normal' ]]; then
	cd "$bak_cfg" || kill_chrome
	tar -cf "$tar_fn" * || kill_chrome
	rm -rf "$bak_cfg" || kill_chrome
fi

cd "$shm_cfg" || kill_chrome

while kill -0 "$pid" 1>&- 2>&-; do
	n=$(( n + 1 ))

	sleep 10

	mapfile -t free_ram < <(free | sed -E 's/[[:blank:]]+/ /g')
	mapfile -d' ' -t ram <<<"${free_ram[1]}"
	ram[-1]="${ram[-1]%$'\n'}"

	if [[ ${ram[6]} -lt $limit ]]; then
		kill_chrome
	fi

	if [[ $n -eq 180 ]]; then
		n=0

		if [[ $mode == 'normal' ]]; then
			if [[ ! -f $tar_fn ]]; then
				kill_chrome
			fi

			cat <<BACKUP

$(date)

Backing up:
${shm_cfg}

To:
${tar_fn} 

BACKUP

			mv "$tar_fn" "${tar_fn}.bak" || kill_chrome
			tar -cf "$tar_fn" *
			rm "${tar_fn}.bak" || kill_chrome
		fi
	fi
done

restore_chrome
