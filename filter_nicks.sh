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

declare -A regex

regex[nick]='^<\+*(.*)>$'
regex[line]='^(\[[[:alpha:]]+, [[:alpha:]]+ [0-9]+, [0-9]+\] \[[0-9]+:[0-9]+:[0-9]+ [[:alpha:]]+ [[:alpha:]]+\])(.*)$'

declare -a lines times
declare -A nicks nicks_tmp

shift

for nick in "$@"; do
	nicks["${nick,,}"]=1
done

if_nick () {
	mapfile -t words < <(sed -E 's/[[:blank:]]+/\n/g' <<<"${line,,}")
	word="${words[1]}"

	if [[ $word =~ ${regex[nick]} ]]; then
		nick="${BASH_REMATCH[1]}"

		printf '%s' "$nick"
	fi
}

mapfile -t lines < <(tr -d '\r' <"$if")

# This loop finds all the nicks in the log and adds them to a hash.
for (( i = 0; i < ${#lines[@]}; i++ )); do
	if [[ ! ${lines[${i}]} =~ ${regex[line]} ]]; then
		continue
	fi

	times["${i}"]="${BASH_REMATCH[1]}"
	lines["${i}"]="${BASH_REMATCH[2]}"

	time="${times[${i}]}"
	line="${lines[${i}]}"

	nick=$(if_nick)

	if [[ -n $nick ]]; then
		nicks_tmp["${nick}"]=1
	fi
done

# This loop finds all the nicks highlighted by the nicks given as
# arguments to the script, and adds them to the nick hash.
for (( i = 0; i < ${#lines[@]}; i++ )); do
	line="${lines[${i}]}"

	nick=$(if_nick)

	if [[ -z $nick ]]; then
		continue
	fi

	for nick_tmp in "${!nicks[@]}"; do
		if [[ $nick == "$nick_tmp" ]]; then
			mapfile -t words < <(sed -E 's/[[:blank:]]+/\n/g' <<<"${line,,}")

			for (( k = 0; k < ${#words[@]}; k++ )); do
				word="${words[${k}]}"

				for nick_tmp_2 in "${!nicks_tmp[@]}"; do
					regex[nick_tmp]="^[[:punct:]]*${nick_tmp_2}[[:punct:]]*$"

					if [[ $word =~ ${regex[nick_tmp]} ]]; then
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
