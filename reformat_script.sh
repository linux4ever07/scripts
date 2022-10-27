#!/bin/bash

# This is just a simple script to reformat / clean up my old shell
# scripts. My formatting style as well as choice of text editor have
# changed over the years. I now use the Geany text editor, which has a
# page width of 72 characters.

# This script will:

# * Replace individual spaces at the beginning of each line with tabs
# (4 spaces / tab).
# * Reduce the number of successive empty lines to a maximum of 1.
# * Remove space at the beginning of comment lines.
# * Reduce multiple #s to just 1 # in comment lines.
# * Remove space at the end of lines.
# * Replace multiple successive spaces in comments with just one space.
# * Reduce the total length of comment lines to 72 characters.

if=$(readlink -f "$1")
bn=$(basename "$if")
session="${RANDOM}-${RANDOM}"
tmp_dn="/dev/shm/reformat_script-${session}"
of="${tmp_dn}/${bn}"
of_tmp="${tmp_dn}/tmp"

limit='72'
regex1='^([[:space:]]*)(#+)([[:space:]]*)'
regex2='^[[:space:]]+'
regex3='[[:space:]]+$'
regex4='( +)'
regex5='^( {4})'
regex6='^#!'

tab=$(printf '\t')
switch='0'

set -eo pipefail

# If the script isn't run with sudo / root privileges, quit.
if [[ $(whoami) != root ]]; then
	printf '\n%s\n\n' "You need to be root to run this script!"
	exit
fi

if [[ ! -f $if ]]; then
	printf '\n%s\n\n' "Usage: $(basename "$0") [file]"
	exit
fi

reformat_comments () {
	switch='0'

	if [[ "$line" =~ $regex1 && ! "$line" =~ $regex6 ]]; then
		j="$i"
		line_tmp="${lines[${j}]}"

		while [[ "$line_tmp" =~ $regex1 ]]; do
			mapfile -d' ' -t line_tmp_array < <(tr -d '\r\n' <<<"$line_tmp" | sed -E -e "s/${regex1}//" -e "s/${regex3}//" -e "s/${regex4}/ /g")
			line_tmp_string="# ${line_tmp_array[@]}"
			line_tmp_chars="${#line_tmp_string}"

			if [[ $line_tmp_chars -gt $limit ]]; then
				switch='1'
			fi

			printf ' %s' "${line_tmp_array[@]}"

			j=$(( j + 1 ))
			line_tmp="${lines[${j}]}"
		done > "$of_tmp"

		if [[ $switch -eq 1 ]]; then
			i=$(( j - 1 ))

			mapfile -d' ' -t line_tmp_array < <(sed -E "s/${regex2}//" <"$of_tmp")

			string_tmp='#'
			char_sum='1'

			end=$(( ${#line_tmp_array[@]} - 1 ))

			for (( k=0; k<${#line_tmp_array[@]}; k++ )); do
				word="${#line_tmp_array[${k}]}"
				word=$(( word + 1 ))

				char_sum=$(( char_sum + word ))

				if [[ $char_sum -le $limit ]]; then
					string_tmp+=" ${line_tmp_array[${k}]}"
				else
					printf '%s\n' "$string_tmp" >> "$of"

					string_tmp="# ${line_tmp_array[${k}]}"
					char_sum=$(( 1 + word ))
				fi

				if [[ $k -eq $end ]]; then
					printf '%s\n' "$string_tmp" >> "$of"
				fi
			done
		fi
	fi
}

reformat_lines () {
	unset -v tmp

	if [[ "$line" =~ $regex1 && ! "$line" =~ $regex6 ]]; then
		line=$(sed -E -e "s/${regex1}/# /" -e "s/${regex4}/ /g" <<<"$line")
	fi

	while [[ "$line" =~ $regex5 ]]; do
		line=$(sed -E "s/${regex5}//" <<<"$line")
		tmp+="$tab"
	done

	line="${tmp}${line}"

	if [[ "$line" =~ $regex3 ]]; then
		line=$(sed -E "s/${regex3}//" <<<"$line")
	fi

	printf '%s\n' "$line" >> "$of"
}

mkdir -p "$tmp_dn"
touch "$of"

mapfile -t lines <"$if"

for (( i=0; i<${#lines[@]}; i++ )); do
	line="${lines[${i}]}"
	j=$(( i - 1 ))
	previous="${lines[${j}]}"

	if [[ -z $line && -z $previous ]]; then
		continue
	fi

	reformat_comments

	if [[ $switch -eq 1 ]]; then
		continue
	else
		reformat_lines
	fi
done

chmod --reference="${if}" "$of"
chown --reference="${if}" "$of"
touch -r "$if" "$of"

mv "$of" "$if"

rm -rf "$tmp_dn"
