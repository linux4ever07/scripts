#!/bin/bash

# This is a script that runs the Google Chrome config / cache from
# /dev/shm (RAM). Running the whole application in RAM like this makes
# it more responsive. However, it's not a good idea to do this unless
# you have lots of RAM.

# The script has 2 modes, 'normal' and 'clean'.

# In 'normal' mode, the script copies over config and cache from $HOME
# to /dev/shm, and later restores it after the Chrome process quits.
# Also, the script updates a backup TAR archive of the /dev/shm config
# directory every 60 minutes, in case of a power outage or OS crash.
# That backup is saved to $HOME. It's not automatically removed when
# the script quits, so you have to remove it manually between each
# session.

# In 'clean' mode, it runs a clean instance of Chrome with a fresh
# config and cache. Whatever changes are made to that config will be
# discarded, and when the Chrome process quits, the original config and
# cache are restored.

# The script also checks the amount of free RAM every 10 seconds, to
# make sure it's not less than 1GB ($ram_limit). If it's less, then
# Chrome will be killed and the config / cache directories restored to
# the hard drive. This is to make sure those directories don't get
# corrupted when there's not enough free space in /dev/shm to write
# files.

# If Chrome were to become unresponsive, 'killall -9 chrome' will allow
# the script to quit normally and restore everything.

usage () {
	printf '\n%s\n\n' "Usage: $(basename "$0") [normal|clean]"
	exit
}

if [[ $# -ne 1 ]]; then
	usage
fi

declare mode restart_fn pid_chrome

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

is_chrome

if [[ $? -eq 0 ]]; then
	printf '\n%s\n\n' 'Chrome is already running!'
	exit
fi

session="${RANDOM}-${RANDOM}"
ram_limit=1000000
time_limit=3600

og_cfg="${HOME}/.config/google-chrome"
og_cache="${HOME}/.cache/google-chrome"

bak_cfg="${og_cfg}-${session}"
bak_cache="${og_cache}-${session}"

shm_dn="/dev/shm/google-chrome-${session}"
shm_cfg="${shm_dn}/config"
shm_cache="${shm_dn}/cache"

restart_fn="${shm_dn}/kill"

tar_fn="${HOME}/google-chrome-${session}.tar"

cwd="$PWD"

is_chrome () {
	declare cmd_stdout

	cmd_stdout=$(ps -C chrome -o pid 2>&1)

	case in "$?"
		'0')
			return 0
		;;
		*)
			return 1
		;;
	esac
}

start_chrome () {
	printf '\n%s\n\n' 'Starting Chrome...'

	google-chrome 1>&- 2>&- &
	pid_chrome="$!"
}

check_status () {
	declare cmd_stdout

	cmd_stdout=$(ps -p "$pid_chrome" 2>&1)

	case in "$?"
		'0')
			return 0
		;;
		*)
			return 1
		;;
	esac
}

check_ram () {
	mapfile -t free_ram < <(free | sed -E 's/[[:blank:]]+/ /g')
	mapfile -d' ' -t ram <<<"${free_ram[1]}"
	ram[-1]="${ram[-1]%$'\n'}"

	if [[ ${ram[6]} -lt $ram_limit ]]; then
		printf '\n%s\n\n' 'Running out of RAM...'

		return 1
	fi

	return 0
}

check_hdd () {
	cfg_size=$(du --summarize --total --block-size=1 "$@" | tail -n 1 | grep -Eo '^[0-9]+')
	hdd_free=$(df --output=avail --block-size=1 "$HOME" | tail -n +2 | tr -d '[:blank:]')

	if [[ $cfg_size -gt $hdd_free ]]; then
		cat <<NOT_ENOUGH

Not enough free space in:
${HOME}

You need to free up space to be able to backup the Chrome config, and to
restore config / cache when Chrome quits.

NOT_ENOUGH

		return 1
	fi

	return 0
}

backup_chrome () {
	tar_fn_old="${tar_fn}.old"

	cat <<BACKUP

$(date)

Backing up:
${shm_cfg}

To:
${tar_fn} 

BACKUP

	if [[ -f $tar_fn ]]; then
		mv "$tar_fn" "$tar_fn_old"
	fi

	tar -cf "$tar_fn" *

	if [[ -f $tar_fn_old ]]; then
		rm "$tar_fn_old"
	fi
}

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

	rm -r "$shm_dn"

	sync
	cd "$cwd"
}

kill_chrome () {
	kill -9 "$pid_chrome"

	restore_chrome

	exit
}

mkdir -p "$og_cfg" "$og_cache" || exit

if [[ $mode == 'normal' ]]; then
	check_hdd "$og_cfg" || exit
fi

mv "$og_cfg" "$bak_cfg" || exit
mv "$og_cache" "$bak_cache" || exit

mkdir -p "$shm_cfg" "$shm_cache" || exit

ln -s "$shm_cfg" "$og_cfg" || exit
ln -s "$shm_cache" "$og_cache" || exit

if [[ $mode == 'normal' ]]; then
	printf '\n%s\n\n' 'Copying Chrome config / cache to /dev/shm...'

	mapfile -t files < <(compgen -G "${bak_cfg}/*")

	if [[ ${#files[@]} -gt 0 ]]; then
		cp -rp "${files[@]}" "$shm_cfg" || exit
	fi

	mapfile -t files < <(compgen -G "${bak_cache}/*")

	if [[ ${#files[@]} -gt 0 ]]; then
		cp -rp "${files[@]}" "$shm_cache" || exit
	fi

	rm -r "$bak_cache" || exit
fi

start_chrome

if [[ $mode == 'normal' ]]; then
	cd "$bak_cfg" || kill_chrome

	mapfile -t files < <(compgen -G "*")

	if [[ ${#files[@]} -gt 0 ]]; then
		tar -cf "$tar_fn" * || kill_chrome
	fi

	rm -r "$bak_cfg" || kill_chrome
fi

cd "$shm_cfg" || kill_chrome

while check_status; do
	if [[ -f $restart_fn ]]; then
		rm "$restart_fn" || exit

		kill -9 "$pid_chrome"

		while is_chrome; do
			sleep 1
		done

		sync

		start_chrome
	fi

	n=$(( n + 1 ))

	sleep 1

	check_ram || kill_chrome

	if [[ $n -eq $time_limit ]]; then
		n=0

		if [[ $mode == 'normal' ]]; then
			check_hdd "$shm_dn" && backup_chrome
		fi
	fi
done

restore_chrome
