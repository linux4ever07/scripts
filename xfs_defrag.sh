#!/bin/bash

# This script is just meant to defrag all my XFS partitions (except the
# root partition). The script generates a menu, allowing me to choose
# which partitions to defrag, and which ones to leave alone.

set -eo pipefail

if [[ $EUID -ne 0 ]]; then
	printf '\n%s\n\n' 'You need to be root to run this script!'
	exit
fi

declare date passes xfs_log
declare -a lines
declare -A regex

regex[digit]='^[[:digit:]]+$'
regex[alpha]='^[[:alpha:]]+$'

date=$(date "+%F")

passes='60'

xfs_log="${HOME}/xfs_defrag_log-${date}_${RANDOM}.txt"

mapfile -t lines < <(mount -t xfs)

xfs_defrag () {
	declare line mount_point partition
	declare -a mount_points partitions_in partitions_out line_parts

	menu () {
		declare n

		if [[ ${#partitions_in[@]} -eq 0 ]]; then
			exit
		fi

		printf '\nChoose partition:\n\n'

		for (( z = 0; z < ${#partitions_in[@]}; z++ )); do
			mount_point="${mount_points[${z}]}"
			partition="${partitions_in[${z}]}"

			printf '%s) %s -> %s\n' "$z" "$partition" "$mount_point"
		done

		printf '\n(a) abort\n(d) done\n\n'

		sleep 0.1
		read -p '>'

		clear

		if [[ $REPLY =~ ${regex[digit]} ]]; then
			mount_point="${mount_points[${REPLY}]}"
			partition="${partitions_in[${REPLY}]}"

			if [[ -z $partition ]]; then
				return
			fi

			n="$REPLY"

			printf '\n*** %s -> %s ***\n\n' "$partition" "$mount_point"
			printf 'Choose action:\n\n'
			printf '(k) keep\n(r) remove\n\n'

			sleep 0.1
			read -p '>'

			if [[ $REPLY == 'r' ]]; then
				unset -v "mount_points[${n}]" "partitions_in[${n}]"

				mount_points=("${mount_points[@]}")
				partitions_in=("${partitions_in[@]}")
			fi

			return
		fi

		if [[ $REPLY =~ ${regex[alpha]} ]]; then
			case "$REPLY" in
				'd')
					partitions_out=("${partitions_in[@]}")
				;;
				'a')
					exit
				;;
			esac

			return
		fi
	}

	for (( i = 0; i < ${#lines[@]}; i++ )); do
		line="${lines[${i}]}"

		mapfile -d' ' -t line_parts <<<"$line"
		line_parts[-1]="${line_parts[-1]%$'\n'}"

		if [[ ${line_parts[2]} == '/' ]]; then
			continue
		fi

		if [[ -b ${line_parts[0]} ]]; then
			mount_points+=("${line_parts[2]}")
			partitions_in+=("${line_parts[0]}")
		fi
	done

	clear

	while [[ ${#partitions_out[@]} -eq 0 ]]; do
		menu

		clear
	done

	touch "$xfs_log"

	for (( i = 0; i < ${#partitions_out[@]}; i++ )); do
		partition="${partitions_out[${i}]}"

		printf '\n%s\n\n' "*** ${partition}"

		xfs_fsr -v -p "$passes" "$partition"
	done | tee --append "$xfs_log"

	for (( i = 0; i < ${#partitions_out[@]}; i++ )); do
		partition="${partitions_out[${i}]}"

		printf '\n%s\n\n' "*** ${partition}"

		xfs_db -c frag -r "$partition"
	done | tee --append "$xfs_log"
}

xfs_defrag
