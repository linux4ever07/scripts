#!/bin/bash

# This script looks through all my disc-based ROMs, updates a folder of
# links to those ROMs, and generates a menu allowing me to select a game
# to load into RAM for faster performance. This is also to avoid I/O
# issues, for example when reading the disc image from the same device
# as an OBS desktop recording is being written to.

# The ROM directory to be scanned in the emulator should be the one in
# the 'link_dn' variable.

set -eo pipefail

declare session link_dn ram_dn system_in system_out elements title_ref size_ref
declare -a systems_in files
declare -A regex systems_out dirs_in dirs_out if of loaded

session="${RANDOM}-${RANDOM}"
link_dn="${HOME}/ROMs_links"
ram_dn="/dev/shm/game2ram-${session}"

regex[digit]='^[[:digit:]]+$'
regex[alpha]='^[[:alpha:]]+$'
regex[du]='^[[:digit:]]+'

systems_in=('pc_engine_cd' 'sega_cd' 'saturn' 'ps1' 'ps2' 'gamecube')

systems_out[pc_engine_cd]='PC Engine CD-ROM²'
systems_out[sega_cd]='Sega CD'
systems_out[saturn]='Sega Saturn'
systems_out[ps1]='PlayStation'
systems_out[ps2]='PlayStation 2'
systems_out[gamecube]='GameCube'

dirs_in[pc_engine_cd]='/home/lucifer/ROMs_files/pc_engine/unpacked'
dirs_in[sega_cd]='/home/lucifer/SSD/ROMs/sega_cd'
dirs_in[saturn]='/run/media/lucifer/2c5518a5-5311-4a7d-8356-206fecd9f13f/ROMs/saturn/unpacked'
dirs_in[ps1]='/home/lucifer/SSD/ROMs/playstation'
dirs_in[ps2]='/run/media/lucifer/2c5518a5-5311-4a7d-8356-206fecd9f13f/ROMs/playstation_2/unpacked'
dirs_in[gamecube]='/run/media/lucifer/SD_BTRFS/SD_BTRFS/gamecube/new'

for system_in in "${systems_in[@]}"; do
	dirs_out["${system_in}"]="${link_dn}/${system_in}"
done

iquit () {
	unload_game

	if [[ -d $ram_dn ]]; then
		rm -rf "$ram_dn"
	fi

	sync

	exit
}

load_game () {
	loaded[system]="$system_out"
	loaded[title]="${!title_ref}"
	loaded[size]="${!size_ref}"
	loaded[link]="${dirs_out[${system_in}]}/${!title_ref}"
	loaded[disk]="${dirs_in[${system_in}]}/${!title_ref}"
	loaded[ram]="${ram_dn}/${!title_ref}"

	cp -Lrp "${loaded[disk]}" "${loaded[ram]}"

	rm -f "${loaded[link]}"

	ln -s "${loaded[ram]}" "${loaded[link]}"
}

unload_game () {
	if [[ ${#loaded[@]} -eq 0 ]]; then
		return
	fi

	rm -rf "${loaded[ram]}"

	rm -f "${loaded[link]}"

	ln -s "${loaded[disk]}" "${loaded[link]}"

	loaded=()
}

menu () {
	declare actions title_ref1 title_ref2 size_ref1 size_ref2 string1 string2

	actions='(a) abort (u) unload (q) quit'

	printf '\nChoose system:\n\n'

	for (( z = 0; z < ${#systems_in[@]}; z++ )); do
		system_in="${systems_in[${z}]}"
		system_out="${systems_out[${system_in}]}"

		printf '%s) %s\n' "$z" "$system_out"
	done

	printf '\nloaded: %s/%s/%s MiB\n\n%s\n\n' "${loaded[system]}" "${loaded[title]}" "${loaded[size]}" "$actions"

	read -p '>'

	clear

	if [[ $REPLY =~ ${regex[digit]} ]]; then
		system_in="${systems_in[${REPLY}]}"
		system_out="${systems_out[${system_in}]}"

		if [[ -z $system_in ]]; then
			return
		fi

		printf '\nChoose (%s) game:\n\n' "$system_out"

		eval elements=$(printf '${#files_%s[@]}' "$system_in")

		for (( y = 0; y < elements; y++ )); do
			z=$(( y + 1 ))

			title_ref1="files_${system_in}[${y}]"
			title_ref2="files_${system_in}[${z}]"

			size_ref1="sizes_${system_in}[${y}]"
			size_ref2="sizes_${system_in}[${z}]"

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
			title_ref="files_${system_in}[${REPLY}]"
			size_ref="sizes_${system_in}[${REPLY}]"

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

for system_in in "${systems_in[@]}"; do
	declare -a "files_${system_in}" "sizes_${system_in}"

	if[dn]="${dirs_in[${system_in}]}"
	of[dn]="${dirs_out[${system_in}]}"

	if [[ ! -d  ${if[dn]} ]]; then
		exit
	fi

	if [[ ! -d  ${of[dn]} ]]; then
		mkdir -p "${of[dn]}"
	fi

	mapfile -t files < <(find "${if[dn]}" -mindepth 1 -maxdepth 1 | sort)

	mapfile -t "files_${system_in}" < <(printf '%s\n' "${files[@]}" | xargs -r -d '\n' basename -a)
	mapfile -t "sizes_${system_in}" < <(printf '%s\n' "${files[@]}" | xargs -r -d '\n' du -B MiB -s | grep -Eo "${regex[du]}")

	eval elements=$(printf '${#files_%s[@]}' "$system_in")

	for (( i = 0; i < elements; i++ )); do
		title_ref="files_${system_in}[${i}]"

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
