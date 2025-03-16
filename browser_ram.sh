#!/bin/bash

# This is a script that runs the web browser config / cache from
# /dev/shm (RAM). Running the whole application in RAM like this makes
# it more responsive. However, it's not a good idea to do this unless
# you have lots of RAM.

# Right now, the script supports these browsers:
# * Chromium
# * Chrome
# * Brave
# * Firefox

# The script has 2 modes, 'normal' and 'clean'.

# In 'normal' mode, the script copies over config and cache from $HOME
# to /dev/shm, and later restores it after the browser process quits.
# Also, the script updates a backup TAR archive of the /dev/shm config
# directory every 60 minutes, in case of a power outage or OS crash.
# That backup is saved to $HOME. It's not automatically removed when
# the script quits, so you have to remove it manually between each
# session.

# In 'clean' mode, it runs a clean instance of the browser with a fresh
# config and cache. Whatever changes are made to that config will be
# discarded, and when the browser process quits, the original config and
# cache are restored.

# The script also checks the amount of free RAM every second, to make
# sure it's not less than 1GB ($ram_limit). If it's less, then the
# browser will be killed and the config / cache directories restored to
# the hard drive. This is to make sure those directories don't get
# corrupted when there's not enough free space in /dev/shm to write
# files.

# If the browser were to become unresponsive, 'killall -9' (+ the
# browser command name) will allow the script to quit normally and
# restore everything. In case the user wants to restart the browser
# quickly, without relaunching the script or touching the hard drive,
# there's an accompanying script to this called 'browser_kill.sh'.

usage () {
	cat <<USAGE

Usage: $(basename "$0") [browser] [mode]

	Browsers:

	chromium
	chrome
	brave
	firefox

	Modes:

	normal
	clean

USAGE

	exit
}

if [[ $# -ne 2 ]]; then
	usage
fi

declare browser cmd name mode session
declare ram_limit time_limit time_start time_end pause_msg cwd pid
declare -a files
declare -A browsers browsers_info if of

browsers[chromium]=1
browsers[chrome]=1
browsers[brave]=1
browsers[firefox]=1

browsers_info[chromium,cmd]='chromium-browser'
browsers_info[chromium,name]='Chromium'
browsers_info[chromium,cfg]="${HOME}/.config/chromium"
browsers_info[chromium,cache]="${HOME}/.cache/chromium"

browsers_info[chrome,cmd]='google-chrome'
browsers_info[chrome,name]='Chrome'
browsers_info[chrome,cfg]="${HOME}/.config/google-chrome"
browsers_info[chrome,cache]="${HOME}/.cache/google-chrome"

browsers_info[brave,cmd]='brave-browser'
browsers_info[brave,name]='Brave'
browsers_info[brave,cfg]="${HOME}/.config/BraveSoftware/Brave-Browser"
browsers_info[brave,cache]="${HOME}/.cache/BraveSoftware/Brave-Browser"

browsers_info[firefox,cmd]='firefox'
browsers_info[firefox,name]='Firefox'
browsers_info[firefox,cfg]="${HOME}/.mozilla"
browsers_info[firefox,cache]="${HOME}/.cache/mozilla"

if [[ -n ${browsers[${1}]} ]]; then
	browser="$1"
else
	usage
fi

cmd="${browsers_info[${browser},cmd]}"
name="${browsers_info[${browser},name]}"

shift

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

is_browser () {
	declare cmd_stdout

	if [[ $browser == 'chrome' ]]; then
		cmd_stdout=$(ps -C chrome -o pid= 2>&1)
	else
		cmd_stdout=$(ps -C "$cmd" -o pid= 2>&1)
	fi

	return "$?"
}

if is_browser; then
	printf '\n%s\n\n' "${name} is already running!"
	exit
fi

session="${RANDOM}-${RANDOM}"
ram_limit=1000000
time_limit=3600

pause_msg="Restart ${name}? [y/n]: "

if[og_cfg]="${browsers_info[${browser},cfg]}"
if[og_cache]="${browsers_info[${browser},cache]}"

if[bak_cfg]="${if[og_cfg]}-${session}"
if[bak_cache]="${if[og_cache]}-${session}"

of[shm_dn]="/dev/shm/${browser}-${session}"
of[shm_cfg]="${of[shm_dn]}/config"
of[shm_cache]="${of[shm_dn]}/cache"

of[restart_fn]="${of[shm_dn]}/kill"
of[tar_fn]="${HOME}/${browser}-${session}.tar"
of[tar_unfinished_fn]="${of[tar_fn]}.unfinished"

cwd="$PWD"

start_browser () {
	sync

	printf '\n%s\n\n' "Starting ${name}..."

	"$cmd" &>/dev/null &
	pid="$!"
}

restart_browser () {
	if [[ ! -f ${of[restart_fn]} ]]; then
		return
	fi

	rm "${of[restart_fn]}" || exit

	kill_browser
	start_browser
}

check_status () {
	declare cmd_stdout

	cmd_stdout=$(ps -p "$pid" -o pid= 2>&1)

	return "$?"
}

check_ram () {
	declare -a free_ram ram

	mapfile -t free_ram < <(free | sed -E 's/[[:blank:]]+/ /g')
	mapfile -d' ' -t ram <<<"${free_ram[1]}"
	ram[-1]="${ram[-1]%$'\n'}"

	if [[ ${ram[6]} -lt $ram_limit ]]; then
		printf '\n%s\n\n' 'Running out of RAM...'

		kill_browser

		printf '\n'

		read -p "$pause_msg" -t 60

		if [[ $REPLY == 'y' ]]; then
			start_browser
		fi

		if [[ $REPLY != 'y' ]]; then
			restore_browser

			exit
		fi
	fi
}

check_time () {
	time_start=$(date '+%s')

	if [[ $time_start -ge $time_end ]]; then
		time_end=$(( time_start + time_limit ))

		return 0
	fi

	return 1
}

check_hdd () {
	declare cfg_size hdd_free

	cfg_size=$(du --summarize --total --block-size=1 "$@" | tail -n 1 | grep -Eo '^[0-9]+')
	hdd_free=$(df --output=avail --block-size=1 "$HOME" | tail -n +2 | tr -d '[:blank:]')

	if [[ $cfg_size -gt $hdd_free ]]; then
		cat <<NOT_ENOUGH

Not enough free space in:
${HOME}

You need to free up space to be able to backup the ${name} config, and
to restore config / cache when ${name} quits.

NOT_ENOUGH

		return 1
	fi

	return 0
}

backup_browser () {
	cat <<BACKUP

$(date)

Backing up:
${of[shm_cfg]}

To:
${of[tar_fn]}

BACKUP

	sync

	mapfile -t files < <(compgen -G "*")

	if [[ ${#files[@]} -gt 0 ]]; then
		tar -cf "${of[tar_unfinished_fn]}" "${files[@]}"
		mv "${of[tar_unfinished_fn]}" "${of[tar_fn]}"
	fi
}

restore_browser () {
	printf '\n%s\n\n' "Restoring ${name} config / cache..."

	sync

	rm "${if[og_cfg]}" "${if[og_cache]}" || exit

	if [[ $mode == 'normal' ]]; then
		mkdir -p "${if[og_cfg]}" "${if[og_cache]}" || exit

		mapfile -t files < <(compgen -G "${of[shm_cfg]}/*")

		if [[ ${#files[@]} -gt 0 ]]; then
			cp -rp "${files[@]}" "${if[og_cfg]}" || exit
		fi

		mapfile -t files < <(compgen -G "${of[shm_cache]}/*")

		if [[ ${#files[@]} -gt 0 ]]; then
			cp -rp "${files[@]}" "${if[og_cache]}" || exit
		fi
	fi

	if [[ $mode == 'clean' ]]; then
		mv "${if[bak_cfg]}" "${if[og_cfg]}" || exit
		mv "${if[bak_cache]}" "${if[og_cache]}" || exit
	fi

	rm -r "${of[shm_dn]}"

	sync

	cd "$cwd"
}

kill_browser () {
	if [[ $browser == 'brave' ]]; then
		killall -9 brave
	else
		kill -9 "$pid"
	fi

	while is_browser; do
		sleep 1
	done
}

iquit () {
	kill_browser
	restore_browser

	exit
}

mkdir -p "${if[og_cfg]}" "${if[og_cache]}" || exit

if [[ $mode == 'normal' ]]; then
	check_hdd "${if[og_cfg]}" || exit
fi

mv "${if[og_cfg]}" "${if[bak_cfg]}" || exit
mv "${if[og_cache]}" "${if[bak_cache]}" || exit

mkdir -p "${of[shm_cfg]}" "${of[shm_cache]}" || exit

ln -s "${of[shm_cfg]}" "${if[og_cfg]}" || exit
ln -s "${of[shm_cache]}" "${if[og_cache]}" || exit

if [[ $mode == 'normal' ]]; then
	printf '\n%s\n\n' "Copying ${name} config / cache to /dev/shm..."

	mapfile -t files < <(compgen -G "${if[bak_cfg]}/*")

	if [[ ${#files[@]} -gt 0 ]]; then
		cp -rp "${files[@]}" "${of[shm_cfg]}" || exit
	fi

	mapfile -t files < <(compgen -G "${if[bak_cache]}/*")

	if [[ ${#files[@]} -gt 0 ]]; then
		cp -rp "${files[@]}" "${of[shm_cache]}" || exit
	fi

	rm -r "${if[bak_cache]}" || exit
fi

start_browser

if [[ $mode == 'normal' ]]; then
	cd "${if[bak_cfg]}" || iquit

	mapfile -t files < <(compgen -G "*")

	if [[ ${#files[@]} -gt 0 ]]; then
		tar -cf "${of[tar_fn]}" "${files[@]}" || iquit
	fi

	rm -r "${if[bak_cfg]}" || iquit
fi

cd "${of[shm_cfg]}" || iquit

time_start=$(date '+%s')
time_end=$(( time_start + time_limit ))

while check_status; do
	restart_browser

	sleep 1

	check_ram

	check_time || continue

	if [[ $mode == 'normal' ]]; then
		check_hdd "${of[shm_dn]}" && backup_browser
	fi
done

restore_browser
