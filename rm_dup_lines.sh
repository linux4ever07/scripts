#!/bin/bash

# This script removes duplicate lines from IRC logs in the current
# directory.

konversation_regex='^\[[[:alpha:]]+, [[:alpha:]]+ [0-9]+, [0-9]+\] \[[0-9]+:[0-9]+:[0-9]+ [[:alpha:]]+ [[:alpha:]]+\]'
irssi_regex='^[0-9]+:[0-9]+'
hexchat_regex='^[[:alpha:]]+ [0-9]+ [0-9]+:[0-9]+:[0-9]+'

dn="/dev/shm/rm_dup_lines-${RANDOM}-${RANDOM}"

mkdir "$dn"

mapfile -t files < <(find . -type f -iname "*.log" -o -iname "*.txt" 2>&-)

for (( i = 0; i < ${#files[@]}; i++ )); do
	fn="${files[${i}]}"
	bn=$(basename "$fn")
	fn_out="${dn}/${bn%.[^.]*}-${RANDOM}-${RANDOM}.log"

	touch "$fn_out"

	unset -v previous

	mapfile -t lines <"$fn"

	for (( j = 0; j < ${#lines[@]}; j++ )); do
		line="${lines[${j}]}"

		unset -v line_tmp

		if [[ $line =~ $konversation_regex ]]; then
			line_tmp=$(sed -E "s/${konversation_regex}//" <<<"$line")
		elif [[ $line =~ $irssi_regex ]]; then
			line_tmp=$(sed -E "s/${irssi_regex}//" <<<"$line")
		elif [[ $line =~ $hexchat_regex ]]; then
			line_tmp=$(sed -E "s/${hexchat_regex}//" <<<"$line")
		fi

		if [[ -z $line_tmp ]]; then
			line_tmp="$line"
		fi

		if [[ $j -ge 1 ]]; then
			if [[ $line_tmp == "$previous" ]]; then
				continue
			fi
		fi

		previous="$line_tmp"

		printf '%s\n' "$line" >> "$fn_out"
	done

	touch -r "$fn" "$fn_out"
	mv "$fn_out" "$fn"
done

rm -rf "$dn"
