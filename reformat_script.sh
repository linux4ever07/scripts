#!/bin/bash

# This is just a simple script to reformat / clean up my old shell
# scripts. My formatting style as well as choice of text editor have
# changed over the years. I now use the Geany text editor, which has a
# page width of 72 characters.

# This script will:

# * Replace individual spaces at the beginning of each line with tabs
# (4 spaces / tab).
# * Reduce the number of successive empty lines to a maximum of 1.
# * Remove space at the end of lines.
# * Remove space at the beginning of comments.
# * Reduce multiple #s to just 1 # in comments.
# * Replace multiple successive spaces in comments with just 1 space.
# * Reduce the total length of comments to 72 characters.

set -eo pipefail

# Creates a function, called 'usage', which will print usage
# instructions and then quit.
usage () {
	printf '\n%s\n\n' "Usage: $(basename "$0") [file]"
	exit
}

# If the script isn't run with sudo / root privileges, quit.
if [[ $EUID -ne 0 ]]; then
	printf '\n%s\n\n' 'You need to be root to run this script!'
	exit
fi

# If argument is not a real file, print usage instructions and then
# quit.
if [[ ! -f $1 ]]; then
	usage
fi

declare if limit tab date line_this line_next
declare -a lines_in lines_out
declare -A regex

if=$(readlink -f "$1")

regex[comment]='^[[:blank:]]*#+[[:blank:]]*'
regex[blank1]='^[[:blank:]]+'
regex[blank2]='[[:blank:]]+$'
regex[blank3]='[[:blank:]]+'
regex[tab]='^ {4}'
regex[shebang]='^#!'

limit=72
tab=$(printf '\t')

# Reads the input file.
mapfile -t lines_in < <(tr -d '\r' <"$if")

# Creates a function, called 'next_line', which will shift the line
# variables by 1 line.
next_line () {
	(( i += 1 ))
	(( j = (i + 1) ))

	line_this="${lines_in[${i}]}"
	line_next="${lines_in[${j}]}"
}

# Creates a function, called 'if_shebang', which will check if the
# current line is a shebang, and add an empty line after if needed.
if_shebang () {
	if [[ $line_this =~ ${regex[shebang]} ]]; then
		lines_out+=("$line_this")

		if [[ -n $line_next ]]; then
			lines_out+=('')
		fi

		next_line
	fi
}

# Creates a function, called 'reformat_comments', which will reformat
# comments if they're longer than the set limit.
reformat_comments () {
	declare start stop switch string chars word
	declare -a words buffer

	start="$i"

	switch=0

	if [[ ! $line_this =~ ${regex[comment]} ]]; then
		lines_out+=("$line_this")

		return
	fi

	while [[ $line_this =~ ${regex[comment]} ]]; do
		mapfile -t words < <(sed -E -e "s/${regex[comment]}//" -e "s/${regex[blank2]}//" -e "s/${regex[blank3]}/\n/g" <<<"$line_this")
		string="# ${words[@]}"
		chars="${#string}"

		if [[ $chars -gt $limit ]]; then
			switch=1
		fi

		buffer+=("${words[@]}")

		next_line
	done

	if [[ $switch -eq 0 ]]; then
		(( stop = (i - start) ))

		lines_out+=("${lines_in[@]:${start}:${stop}}")
	fi

	if [[ $switch -eq 1 ]]; then
		string='#'
		chars=1

		for (( k = 0; k < ${#buffer[@]}; k++ )); do
			word="${buffer[${k}]}"

			(( chars += (${#word} + 1) ))

			if [[ $chars -le $limit ]]; then
				string+=" ${word}"
			else
				lines_out+=("$string")

				string="# ${word}"
				(( chars = (${#word} + 2) ))
			fi
		done

		lines_out+=("$string")
	fi

	(( i -= 1 ))
}

# Creates a function, called 'reformat_lines', which will fix
# indentation among other things.
reformat_lines () {
	declare indent

	if [[ $line_this =~ ${regex[comment]} ]]; then
		line_this=$(sed -E -e "s/${regex[comment]}/# /" -e "s/${regex[blank3]}/ /g" <<<"$line_this")
	fi

	while [[ $line_this =~ ${regex[tab]} ]]; do
		line_this=$(sed -E "s/${regex[tab]}//" <<<"$line_this")
		indent+="$tab"
	done

	line_this="${indent}${line_this}"

	if [[ $line_this =~ ${regex[blank2]} ]]; then
		line_this=$(sed -E "s/${regex[blank2]}//" <<<"$line_this")
	fi

	lines_out+=("$line_this")
}

# Creates a function, called 'reset_arrays', which will reset the line
# arrays in-between loops.
reset_arrays () {
	lines_in=("${lines_out[@]}")
	lines_out=()
}

for (( i = 0; i < ${#lines_in[@]}; i++ )); do
	(( j = (i + 1) ))

	line_this="${lines_in[${i}]}"
	line_next="${lines_in[${j}]}"

	if_shebang

	if [[ -z $line_this && -z $line_next ]]; then
		continue
	fi

	reformat_comments
done

reset_arrays

for (( i = 0; i < ${#lines_in[@]}; i++ )); do
	(( j = (i + 1) ))

	line_this="${lines_in[${i}]}"
	line_next="${lines_in[${j}]}"

	if_shebang

	reformat_lines
done

# If the last line is not empty, add an empty line.
#if [[ -n ${lines_out[-1]} ]]; then
#	lines_out+=('')
#fi

# Gets the modification time of the input file.
date=$(date -R -r "$if")

# Truncates the input file.
truncate -s 0 "$if"

# Prints the altered lines to the input file.
printf '%s\n' "${lines_out[@]}" > "$if"

# Copies the original modification time to the changed file.
touch -d "$date" "$if"
