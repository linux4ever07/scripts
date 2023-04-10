#!/bin/bash

# This script is meant to filter out nicks from Konversation IRC log
# excerpts, except the nicks given as arguments, and whatever other
# nicks those nicks highlight. The purpose is to highlight a specific
# conversation going on between the nicks specified.

# Creates a function called 'usage', which will print usage and quit.
usage () {
	printf '\n%s\n\n' "Usage: $(basename "$0") [log] [nicks...]"
	exit
}

# Checks if the arguments are in order.
if [[ $# -lt 2 || ! -f $1 ]]; then
	usage
fi

if=$(readlink -f "$1")
if_bn=$(basename "$if")
of="${if_bn%.[^.]*}-${RANDOM}-${RANDOM}.txt"

declare line nick nick_utf8
declare -a lines times words
declare -A regex nicks nicks_tmp

regex[nick]='^<\+*(.*)>$'
regex[line]='^(\[[[:alpha:]]+, [[:alpha:]]+ [0-9]+, [0-9]+\] \[[0-9]+:[0-9]+:[0-9]+ [[:alpha:]]+ [[:alpha:]]+\])(.*)$'

# Creates a function called 'get_nick', which will print the nick this
# line belongs to.
get_nick () {
	word="${words[1]}"

	if [[ $word =~ ${regex[nick]} ]]; then
		printf '%s' "${BASH_REMATCH[1]}"
	fi
}

# Creates a function called 'utf8_convert', which will convert all
# characters in the nick to their UTF8 code. This is to be able to use
# the nick as a hash element name, even if the nick contains special
# characters.
utf8_convert () {
	string_in="$@"
	declare string_out

	for (( z = 0; z < ${#string_in}; z++ )); do
		char_tmp="${string_in:${z}:1}"

		string_out+=$(printf '_%X' "'${char_tmp}")
	done

	printf '%s' "$string_out"
}

# Creates a function called 'set_vars', which will split the current
# line into words, and get the nick this line belongs to.
set_vars () {
	mapfile -t words < <(sed -E 's/[[:blank:]]+/\n/g' <<<"${line,,}")

	nick=$(get_nick)
	nick_utf8=$(utf8_convert "$nick")
}

shift

for nick in "$@"; do
	nick_utf8=$(utf8_convert "${nick,,}")
	nicks["${nick_utf8}"]="${nick,,}"
done

mapfile -t lines < <(tr -d '\r' <"$if")

# This loop finds all the nicks in the log and adds them to a hash.
for (( i = 0; i < ${#lines[@]}; i++ )); do
	if [[ ! ${lines[${i}]} =~ ${regex[line]} ]]; then
		continue
	fi

	times["${i}"]="${BASH_REMATCH[1]}"
	lines["${i}"]="${BASH_REMATCH[2]}"

	line="${lines[${i}]}"

	set_vars

	if [[ -n $nick_utf8 ]]; then
		nicks_tmp["${nick_utf8}"]="$nick"
	fi
done

# This loop finds all the nicks highlighted by the nicks given as
# arguments to the script, and adds them to the nick hash.
for (( i = 0; i < ${#lines[@]}; i++ )); do
	line="${lines[${i}]}"

	set_vars

	if [[ -z $nick_utf8 ]]; then
		continue
	fi

	nick_ref="nicks[${nick_utf8}]"

	if [[ -z ${!nick_ref} ]]; then
		continue
	fi

	for nick_tmp in "${nicks_tmp[@]}"; do
		regex[nick_tmp]="^[[:punct:]]*${nick_tmp}[[:punct:]]*$"

		for word in "${words[@]}"; do
			if [[ $word =~ ${regex[nick_tmp]} ]]; then
				nick_tmp_utf8=$(utf8_convert "$nick_tmp")
				nicks["${nick_tmp_utf8}"]="${nick_tmp}"

				break
			fi
		done
	done
done

# This loop prints all the lines that match the nicks collected by
# the previous loop.
for (( i = 0; i < ${#lines[@]}; i++ )); do
	time="${times[${i}]}"
	line="${lines[${i}]}"

	set_vars

	if [[ -z $nick_utf8 ]]; then
		continue
	fi

	nick_ref="nicks[${nick_utf8}]"

	if [[ -n ${!nick_ref} ]]; then
		printf '%s\n' "${time}${line}"
	fi
done | tee "$of"
