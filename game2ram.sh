#!/bin/bash

# This script looks through all my disc-based ROMs, updates a folder of
# links to those ROMs, and generates a menu allowing me to select a game
# to load into RAM for faster performance. This is also to avoid I/O
# issues, for example when reading the disc image from the same device
# as an OBS desktop recording is being written to.

# The ROM directory to be scanned in the emulator should be the one in
# the 'link_dn' variable.

set -eo pipefail

declare session link_dn ram_dn system elements title_ref size_ref
declare -a systems files
declare -A regex dirs_in dirs_out if of loaded

session="${RANDOM}-${RANDOM}"
link_dn="${HOME}/ROMs_links"
ram_dn="/dev/shm/game2ram-${session}"

systems=('Saturn' 'PS1' 'PS2' 'Gamecube')

regex[digit]='^[[:digit:]]+$'
regex[alpha]='^[[:alpha:]]+$'
regex[du]='^[[:digit:]]+'

dirs_in[Saturn]='/run/media/lucifer/2c5518a5-5311-4a7d-8356-206fecd9f13f/ROMs/saturn/unpacked'
dirs_in[PS1]='/home/lucifer/SSD/ROMs/playstation'
dirs_in[PS2]='/run/media/lucifer/2c5518a5-5311-4a7d-8356-206fecd9f13f/ROMs/playstation_2/unpacked'
dirs_in[Gamecube]='/run/media/lucifer/SD_BTRFS/SD_BTRFS/gamecube/new'

dirs_out[Saturn]="${link_dn}/saturn"
dirs_out[PS1]="${link_dn}/ps1"
dirs_out[PS2]="${link_dn}/ps2"
dirs_out[Gamecube]="${link_dn}/gamecube"

iquit () {
	unload_game

	if [[ -d $ram_dn ]]; then
		rm -rf "$ram_dn"
	fi

	sync

	exit
}

load_game () {
	loaded[system]="$system"
	loaded[title]="${!title_ref}"
	loaded[size]="${!size_ref}"
	loaded[link]="${dirs_out[${system}]}/${!title_ref}"
	loaded[disk]="${dirs_in[${system}]}/${!title_ref}"
	loaded[ram]="${ram_dn}/${!title_ref}"

	cp -Lrp "${loaded[disk]}" "${loaded[ram]}"

	rm -f "${loaded[link]}"

	ln -s "${loaded[ram]}" "${loaded[link]}"
}

unload_game () {
	if [[ -n ${loaded[ram]} ]]; then
		rm -rf "${loaded[ram]}"

		rm -f "${loaded[link]}"

		ln -s "${loaded[disk]}" "${loaded[link]}"

		loaded=()
	fi
}

menu () {
	declare actions title_ref1 title_ref2 size_ref1 size_ref2 string1 string2

	actions='(a) abort (u) unload (q) quit'

	printf '\nChoose system:\n\n'

	for (( z = 0; z < ${#systems[@]}; z++ )); do
		system="${systems[${z}]}"

		printf '%s) %s\n' "$z" "$system"
	done

	printf '\nloaded: %s/%s/%s MiB\n\n%s\n\n' "${loaded[system]}" "${loaded[title]}" "${loaded[size]}" "$actions"

	read -p '>'

	clear

	if [[ $REPLY =~ ${regex[digit]} ]]; then
		system="${systems[${REPLY}]}"

		if [[ -z $system ]]; then
			return
		fi

		printf '\nChoose (%s) game:\n\n' "$system"

		eval elements=$(printf '${#files_%s[@]}' "$system")

		for (( y = 0; y < elements; y++ )); do
			z=$(( y + 1 ))

			title_ref1="files_${system}[${y}]"
			title_ref2="files_${system}[${z}]"

			size_ref1="sizes_${system}[${y}]"
			size_ref2="sizes_${system}[${z}]"

			string1="${y}) ${!title_ref1:0:50} (${!size_ref1} MiB)"
			string2="${z}) ${!title_ref2:0:50} (${!size_ref2} MiB)"

			if [[ -n ${!title_ref2} ]]; then
				printf '%-75s %s\n' "$string1" "$string2"
			else
				printf '%s\n' "$string1"
			fi

			y=$(( y + 1 ))
		done

		printf '\nloaded: %s/%s/%s MiB\n\n%s\n\n' "${loaded[system]}" "${loaded[title]}" "${loaded[size]}" "$actions"

		read -p '>'

		clear

		if [[ $REPLY =~ ${regex[digit]} ]]; then
			title_ref="files_${system}[${REPLY}]"
			size_ref="sizes_${system}[${REPLY}]"

			if [[ -z ${!title_ref} ]]; then
				return
			fi

			unload_game
			load_game

			sync
		fi
	fi

	if [[ $REPLY =~ ${regex[alpha]} ]]; then
		case "$REPLY" in
			'u')
				unload_game

				return
			;;
			'q')
				iquit
			;;
			*)
				return
			;;
		esac
	fi
}

trap iquit SIGINT SIGTERM

mkdir "$ram_dn"

for system in "${systems[@]}"; do
	declare -a "files_${system}" "sizes_${system}"

	if[dn]="${dirs_in[${system}]}"
	of[dn]="${dirs_out[${system}]}"

	if [[ ! -d  ${if[dn]} ]]; then
		exit
	fi

	if [[ ! -d  ${of[dn]} ]]; then
		mkdir -p "${of[dn]}"
	fi

	mapfile -t files < <(find "${if[dn]}" -mindepth 1 -maxdepth 1 | sort)

	mapfile -t "files_${system}" < <(printf '%s\n' "${files[@]}" | xargs -r -d '\n' basename -a)
	mapfile -t "sizes_${system}" < <(printf '%s\n' "${files[@]}" | xargs -r -d '\n' du -B MiB -s | grep -Eo "${regex[du]}")

	eval elements=$(printf '${#files_%s[@]}' "$system")

	for (( i = 0; i < elements; i++ )); do
		title_ref="files_${system}[${i}]"

		if[disk]=$(readlink -f "${if[dn]}/${!title_ref}")
		of[link]="${of[dn]}/${!title_ref}"
		of[disk]=$(readlink -f "${of[link]}")

		if [[ ! -L ${of[link]} ]]; then
			rm -f "${of[link]}"

			ln -s "${if[disk]}" "${of[link]}"

			continue
		fi

		if [[ ${if[disk]} != "${of[disk]}" ]]; then
			rm -f "${of[link]}"

			ln -s "${if[disk]}" "${of[link]}"

			continue
		fi
	done
done

unset -v files

sync

while [[ 1 ]]; do
	clear

	menu
done
