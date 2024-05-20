#!/bin/bash

# This script is meant to filter out nicks from IRC log excerpts, except
# the nicks given as arguments, and whatever other nicks those nicks
# highlight. The purpose is to highlight a specific conversation going
# on between the nicks specified.

# Creates a function, called 'usage', which will print usage
# instructions and then quit.
usage () {
	printf '\n%s\n\n' "Usage: $(basename "$0") [log] [nicks...]"
	exit
}

# Checks if the arguments are in order.
if [[ $# -lt 2 || ! -f $1 ]]; then
	usage
fi

declare time line word nick nick_tmp nick_ref nick_utf8 nick_tmp_utf8
declare -a times lines words clients
declare -A if of regex nicks nicks_tmp

if[fn]=$(readlink -f "$1")
if[bn]=$(basename "${if[fn]}")
of[fn]="${if[bn]%.*}-${RANDOM}-${RANDOM}.txt"

regex[nick]='^<\+*(.*)>$'

clients=('hexchat' 'irccloud' 'irssi' 'konversation')

regex[hexchat]='^([[:alpha:]]+ [0-9]+ [0-9]+:[0-9]+:[0-9]+)(.*)$'
regex[irccloud]='^(\[[0-9]+-[0-9]+-[0-9]+ [0-9]+:[0-9]+:[0-9]+\])(.*)$'
regex[irssi]='^([0-9]+:[0-9]+)(.*)$'
regex[konversation]='^(\[[[:alpha:]]+, [[:alpha:]]+ [0-9]+, [0-9]+\] \[[0-9]+:[0-9]+:[0-9]+ [[:alpha:]]+ [[:alpha:]]+\])(.*)$'

# Creates a function, called 'get_client', which will figure out which
# client was used to generate the IRC log in question, to be able to
# parse it correctly.
get_client () {
	declare client switch

	switch=0

	for (( z = 0; z < ${#lines[@]}; z++ )); do
		line="${lines[${z}]}"

		for client in "${clients[@]}"; do
			if [[ ! $line =~ ${regex[${client}]} ]]; then
				continue
			fi

			regex[client]="${regex[${client}]}"
			switch=1

			break
		done

		if [[ $switch -eq 1 ]]; then
			break
		fi
	done
}

# Creates a function, called 'get_nick', which will print the nick this
# line belongs to.
get_nick () {
	declare word

	word="${words[1]}"

	if [[ $word =~ ${regex[nick]} ]]; then
		printf '%s' "${BASH_REMATCH[1]}"
	fi
}

# Creates a function, called 'utf8_convert', which will convert all
# characters in the nick to their UTF8 code. This is to be able to use
# the nick as a hash element name, even if the nick contains special
# characters.
utf8_convert () {
	declare char_tmp string_in string_out

	string_in="$@"

	for (( z = 0; z < ${#string_in}; z++ )); do
		char_tmp="${string_in:${z}:1}"

		string_out+=$(printf '_%X' "'${char_tmp}")
	done

	printf '%s' "$string_out"
}

# Creates a function, called 'set_vars', which will get the current
# line, split it into words, and get the nick it belongs to.
set_vars () {
	time="${times[${i}]}"
	line="${lines[${i}]}"

	mapfile -t words < <(sed -E 's/[[:blank:]]+/\n/g' <<<"${line,,}")

	nick=$(get_nick)
	nick_utf8=$(utf8_convert "$nick")
}

shift

for nick in "$@"; do
	nick_utf8=$(utf8_convert "${nick,,}")
	nicks["${nick_utf8}"]="${nick,,}"
done

mapfile -t lines < <(tr -d '\r' <"${if[fn]}")

get_client

if [[ -z ${regex[client]} ]]; then
	exit
fi

# This loop finds all the nicks in the log and adds them to a hash.
for (( i = 0; i < ${#lines[@]}; i++ )); do
	if [[ ! ${lines[${i}]} =~ ${regex[client]} ]]; then
		continue
	fi

	times["${i}"]="${BASH_REMATCH[1]}"
	lines["${i}"]="${BASH_REMATCH[2]}"

	set_vars

	if [[ -n $nick_utf8 ]]; then
		nicks_tmp["${nick_utf8}"]="$nick"
	fi
done

# This loop finds all the nicks highlighted by the nicks given as
# arguments to the script, and adds them to the nick hash.
for (( i = 0; i < ${#lines[@]}; i++ )); do
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
			if [[ ! $word =~ ${regex[nick_tmp]} ]]; then
				continue
			fi

			nick_tmp_utf8=$(utf8_convert "$nick_tmp")
			nicks["${nick_tmp_utf8}"]="${nick_tmp}"

			break
		done
	done
done

# This loop prints all the lines that match the nicks collected by
# the previous loop.
for (( i = 0; i < ${#lines[@]}; i++ )); do
	set_vars

	if [[ -z $nick_utf8 ]]; then
		continue
	fi

	nick_ref="nicks[${nick_utf8}]"

	if [[ -n ${!nick_ref} ]]; then
		printf '%s\n' "${time}${line}"
	fi
done | tee "${of[fn]}"
