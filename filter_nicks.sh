#!/bin/bash

# This script is meant to filter out nicks from IRC logs, except the
# nicks given as arguments, and whatever other nicks those nicks
# highlight. The purpose is to highlight a specific conversation going
# on between the nicks specified.

if=$(readlink -f "$1")
of="${if%.[^.]*}-${RANDOM}-${RANDOM}.txt"

usage () {
	printf '\n%s\n\n' "Usage: $(basename "$0") [log] [nicks...]"
	exit
}

if [[ ! -f $if || -z $2 ]]; then
	usage
fi

regex1='^<'
regex2='^<\+*(.*)>$'
regex3='[:,.?!]+$'

switch=0

shift

declare -A nicks nicks_tmp

for nick in "$@"; do
	nicks["${nick,,}"]=1
done

if_nick () {
	if [[ $line_tmp =~ $regex1 ]]; then
		nick="${line_tmp%% *}"
		nick=$(sed -E "s/${regex2}/\1/" <<<"$nick")

		printf '%s' "${nick,,}"
	fi
}

mapfile -t lines <"$if"

# This loop finds all the nicks in the log and adds them to a hash.
for (( i = 0; i < ${#lines[@]}; i++ )); do
	line="${lines[${i}]}"

	if [[ $switch -eq 0 ]]; then
		line_tmp="$line"

		n=0

		until [[ $line_tmp =~ $regex1 || $n -eq ${#line_tmp} ]]; do
			line_tmp="${line:${n}}"
			n=$(( n + 1 ))
		done

		if [[ $n -lt ${#line_tmp} ]]; then
			switch=1
		else
			continue
		fi

		unset -v line_tmp

		if [[ $n -gt 0 ]]; then
			n=$(( n - 1 ))
		fi
	fi

	line_tmp="${line:${n}}"

	nick=$(if_nick)

	if [[ -z $nick ]]; then
		continue
	fi

	nicks_tmp["${nick}"]=1
done

# This loop finds all the nicks highlighted by the nicks given as
# arguments to the script, and adds them to the nick hash.
for (( i = 0; i < ${#lines[@]}; i++ )); do
	line="${lines[${i}]}"
	line_tmp="${line:${n}}"

	nick=$(if_nick)

	if [[ -z $nick ]]; then
		continue
	fi

	for nick_tmp in "${!nicks[@]}"; do
		if [[ $nick == "$nick_tmp" ]]; then
			mapfile -d' ' -t line_array < <(sed -E 's/[[:blank:]]+/ /g' <<<"${line_tmp,,}")

			for (( k = 0; k < ${#line_array[@]}; k++ )); do
				word=$(sed -E "s/${regex3}//" <<<"${line_array[${k}]}")

				for nick_tmp_2 in "${!nicks_tmp[@]}"; do
					if [[ $word == "$nick_tmp_2" ]]; then
						nicks["${nick_tmp_2}"]=1

						break
					fi
				done
			done

			break
		fi
	done
done

# This loop prints all the lines that match the nicks collected by
# the previous loop.
for (( i = 0; i < ${#lines[@]}; i++ )); do
	line="${lines[${i}]}"
	line_tmp="${line:${n}}"

	nick=$(if_nick)

	if [[ -z $nick ]]; then
		continue
	fi

	for nick_tmp in "${!nicks[@]}"; do
		if [[ $nick == "$nick_tmp" ]]; then
			printf '%s\n' "$line"
		fi
	done
done | tee "$of"
