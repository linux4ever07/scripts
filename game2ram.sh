#!/bin/bash

# This script looks through folders of disc-based (game) ROMs, updates a
# folder of symbolic links to those ROMs, and generates a menu allowing
# the user to select a game to load into RAM for faster performance.
# This is also to avoid I/O issues, for example when reading the disc
# image from the same device as an OBS desktop recording is being
# written to.

# It's possible to load multiple games at a time, or load a range of
# games at a time, like this:
# 1,2,3,10 or 1-3.

# This gives the user the ability to load multi-disc games. As an
# example, some games for PlayStation span across multiple CDs or DVDs.

# To add a different system, or remove a system, just edit the
# 'add_system' lines in this script. The syntax is:
# add_system 'basic_system_name' 'Real System Name' 'directory'

# The ROM directory to be scanned in the emulator should be the one in
# the 'output[link_dn]' variable. That's the directory of links, that's
# automatically generated and updated. It points to this path by
# default:
# ~/ROMs_links

set -eo pipefail

declare session elements
declare -a systems_in systems_out files loaded_system_keys loaded_title_keys
declare -A input output regex dirs_in dirs_out current refs

session="${RANDOM}-${RANDOM}"
output[link_dn]="${HOME}/ROMs_links"
output[ram_dn]="/dev/shm/game2ram-${session}"

regex[digit]='^[[:digit:]]+$'
regex[alpha]='^[[:alpha:]]+$'
regex[list]='^([[:digit:]]+)([[:punct:]]){0,1}(.*)$'
regex[du]='^[[:digit:]]+'

add_system () {
	systems_in+=("$1")
	systems_out+=("$2")
	dirs_in["${1}"]="$3"
	dirs_out["${1}"]="${output[link_dn]}/${1}"
}

add_system 'pc_engine_cd' 'PC Engine CD-ROM²' '/run/media/lucifer/2c5518a5-5311-4a7d-8356-206fecd9f13f/ROMs/pc_engine_cd/unpacked'
add_system 'amiga_cd32' 'Amiga CD³²' '/home/lucifer/SSD/ROMs/amiga_cd32'
add_system 'sega_cd' 'Sega CD' '/run/media/lucifer/2c5518a5-5311-4a7d-8356-206fecd9f13f/ROMs/sega_cd/unpacked'
add_system 'saturn' 'Sega Saturn' '/run/media/lucifer/2c5518a5-5311-4a7d-8356-206fecd9f13f/ROMs/saturn/unpacked'
add_system 'ps1' 'PlayStation' '/run/media/lucifer/2c5518a5-5311-4a7d-8356-206fecd9f13f/ROMs/playstation/unpacked'
add_system 'ps2' 'PlayStation 2' '/run/media/lucifer/2c5518a5-5311-4a7d-8356-206fecd9f13f/ROMs/playstation_2/unpacked'
add_system 'gamecube' 'GameCube' '/run/media/lucifer/SD_BTRFS/SD_BTRFS/gamecube/new'

iquit () {
	unload_games

	if [[ -d ${output[ram_dn]} ]]; then
		rm -rf "${output[ram_dn]}"
	fi

	sync

	exit
}

relink () {
	rm -f "${output[link_fn]}"

	ln -s "${input[disk_fn]}" "${output[link_fn]}"
}

init_refs () {
	refs[system_key]="$1"
	refs[system_in]="systems_in[${!refs[system_key]}]"
	refs[system_out]="systems_out[${!refs[system_key]}]"

	refs[title_key]="$2"
	refs[title]="files_${!refs[system_in]}[${!refs[title_key]}]"
	refs[size]="sizes_${!refs[system_in]}[${!refs[title_key]}]"
}

unload_games () {
	if [[ ${#loaded_title_keys[@]} -eq 0 ]]; then
		return
	fi

	for (( z = 0; z < ${#loaded_title_keys[@]}; z++ )); do
		init_refs "loaded_system_keys[${z}]" "loaded_title_keys[${z}]"

		input[disk_fn]="${dirs_in[${!refs[system_in]}]}/${!refs[title]}"
		input[link_fn]="${dirs_out[${!refs[system_in]}]}/${!refs[title]}"
		output[ram_fn]="${output[ram_dn]}/${!refs[title]}"

		rm -rf "${output[ram_fn]}"

		rm -f "${input[link_fn]}"

		ln -s "${input[disk_fn]}" "${input[link_fn]}"
	done

	loaded_system_keys=()
	loaded_title_keys=()
}

load_games () {
	declare -a args

	args=("$@")

	for (( z = 0; z < ${#args[@]}; z++ )); do
		init_refs 'current[system_key]' "args[${z}]"

		if [[ -z ${!refs[title]} ]]; then
			return
		fi
	done

	unload_games

	for (( z = 0; z < ${#args[@]}; z++ )); do
		init_refs 'current[system_key]' "args[${z}]"

		loaded_system_keys+=("${!refs[system_key]}")
		loaded_title_keys+=("${!refs[title_key]}")

		input[disk_fn]="${dirs_in[${current[system_in]}]}/${!refs[title]}"
		input[link_fn]="${dirs_out[${current[system_in]}]}/${!refs[title]}"
		output[ram_fn]="${output[ram_dn]}/${!refs[title]}"

		cp -Lrp "${input[disk_fn]}" "${output[ram_fn]}"

		rm -f "${input[link_fn]}"

		ln -s "${output[ram_fn]}" "${input[link_fn]}"
	done

	sync
}

print_loaded () {
	if [[ ${#loaded_title_keys[@]} -eq 0 ]]; then
		return
	fi

	printf '\nLoaded:\n\n'

	for (( z = 0; z < ${#loaded_title_keys[@]}; z++ )); do
		init_refs "loaded_system_keys[${z}]" "loaded_title_keys[${z}]"

		printf '%s/%s/%s MiB\n' "${!refs[system_out]}" "${!refs[title]}" "${!refs[size]}"
	done
}

menu () {
	declare actions string1 string2 key mode
	declare -a list_in list_out

	actions='(a) abort (u) unload (q) quit'
	mode='list'

	printf '\nChoose system:\n\n'

	for (( z = 0; z < ${#systems_in[@]}; z++ )); do
		refs[system_in]="systems_in[${z}]"
		refs[system_out]="systems_out[${z}]"

		printf '%s) %s\n' "$z" "${!refs[system_out]}"
	done

	print_loaded
	printf '\n%s\n\n' "$actions"

	read -p '>'

	key=$(tr -d '[:space:]' <<<"$REPLY")

	clear

	if [[ $key =~ ${regex[alpha]} ]]; then
		case "$key" in
			'u')
				unload_games

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

	if [[ $key =~ ${regex[digit]} ]]; then
		current[system_key]="$key"
		current[system_in]="${systems_in[${key}]}"
		current[system_out]="${systems_out[${key}]}"

		if [[ -z ${current[system_in]} ]]; then
			return
		fi

		eval elements=$(printf '${#files_%s[@]}' "${current[system_in]}")

		if [[ $elements -eq 0 ]]; then
			return
		fi

		printf '\nChoose (%s) game(s):\n\n' "${current[system_out]}"

		for (( y = 0; y < elements; y++ )); do
			z=$(( y + 1 ))

			refs[title1]="files_${current[system_in]}[${y}]"
			refs[title2]="files_${current[system_in]}[${z}]"

			refs[size1]="sizes_${current[system_in]}[${y}]"
			refs[size2]="sizes_${current[system_in]}[${z}]"

			string1="${y}) ${!refs[title1]:0:50} (${!refs[size1]} MiB)"
			string2="${z}) ${!refs[title2]:0:50} (${!refs[size2]} MiB)"

			if [[ -n ${!refs[title2]} ]]; then
				printf '%-75s %s\n' "$string1" "$string2"
			else
				printf '%s\n' "$string1"
			fi

			y=$(( y + 1 ))
		done

		print_loaded
		printf '\n%s\n\n' "$actions"

		read -p '>'

		key=$(tr -d '[:space:]' <<<"$REPLY")

		clear

		if [[ $key =~ ${regex[alpha]} ]]; then
			case "$key" in
				'u')
					unload_games

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

		while [[ $key =~ ${regex[list]} ]]; do
			list_in+=("${BASH_REMATCH[1]}")

			key="${BASH_REMATCH[3]}"

			if [[ -z ${BASH_REMATCH[2]} ]]; then
				continue
			fi

			case "${BASH_REMATCH[2]}" in
				',')
					mode='list'
				;;
				'-')
					mode='range'
				;;
				*)
					return
				;;
			esac
		done

		if [[ ${#list_in[@]} -eq 0 ]]; then
			return
		fi

		if [[ $mode == 'range' && ${#list_in[@]} -eq 2 ]]; then
			if [[ ${list_in[0]} -gt ${list_in[1]} ]]; then
				return
			fi

			(( list_in[1] += 1 ))

			for (( z = list_in[0]; z < list_in[1]; z++ )); do
				list_out+=("$z")
			done
		else
			list_out=("${list_in[@]}")
		fi

		load_games "${list_out[@]}"
	fi
}

trap iquit SIGINT SIGTERM

mkdir "${output[ram_dn]}"

for (( i = 0; i < ${#systems_in[@]}; i++ )); do
	refs[system_in]="systems_in[${i}]"

	declare -a "files_${!refs[system_in]}" "sizes_${!refs[system_in]}"

	input[dn]="${dirs_in[${!refs[system_in]}]}"
	output[dn]="${dirs_out[${!refs[system_in]}]}"

	if [[ ! -d  ${input[dn]} ]]; then
		printf '\nNot found:\n%s\n\n' "${input[dn]}"

		exit
	fi

	if [[ ! -d  ${output[dn]} ]]; then
		mkdir -p "${output[dn]}"
	fi

	mapfile -t files < <(find "${input[dn]}" -mindepth 1 -maxdepth 1 | sort)

	mapfile -t "files_${!refs[system_in]}" < <(printf '%s\n' "${files[@]}" | xargs -r -d '\n' basename -a)
	mapfile -t "sizes_${!refs[system_in]}" < <(printf '%s\n' "${files[@]}" | xargs -r -d '\n' du -B MiB -s | grep -Eo "${regex[du]}")

	eval elements=$(printf '${#files_%s[@]}' "${!refs[system_in]}")

	for (( j = 0; j < elements; j++ )); do
		refs[title]="files_${!refs[system_in]}[${j}]"

		input[disk_fn]=$(readlink -f "${input[dn]}/${!refs[title]}")
		output[link_fn]="${output[dn]}/${!refs[title]}"
		output[disk_fn]=$(readlink -m "${output[link_fn]}")

		if [[ ! -L ${output[link_fn]} ]]; then
			relink

			continue
		fi

		if [[ ${input[disk_fn]} != "${output[disk_fn]}" ]]; then
			relink

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
