#!/bin/bash

# This script will look for all files in directory given as first
# argument, sort them by smallest > largest, and put that list in an
# array. We will then go through that array and copy each file one by
# one to the output directory. The script will check the MD5 hashes of
# all the files to avoid copying duplicates (in order to save space in
# the output directory).

# This script can be useful when dumping the content of failing hard
# drives or broken partitions. The script outputs a list of files that
# were copied, and a list of files that couldn't be copied, in the
# output directory.

# Since the script copies the smallest files first, the highest possible
# number of files will be copied (preferably all of the files). This is
# because smaller files are faster to read / write, and there's
# statistically a smaller chance of a bad block / sector hitting a small
# file. By copying the smaller files first, if the hard drive really is
# about to fail, the largest possible number of files will be copied.

# If the script has problems reading a file, it will retry reading it a
# maximum of 10 times, 5 times to check the MD5 hash, and 5 times to
# copy the file.

# Permissions and modification dates of the input files are preserved in
# the output files by the script.

# PS: It's probably a better idea to use 'ddrescue' than this script, to
# make a complete file system image of the failing drive (using multiple
# passes). But in case there's not enough free space on the destination
# drive, maybe the script could still be useful.

set -o pipefail

# Creates a function called 'usage', which will print usage instructions
# and then quit.
usage () {
	printf '\n%s\n\n' "Usage: $(basename "$0") [in_dir] [out_dir]"
	exit
}

# If the script isn't run with sudo / root privileges, then quit.
if [[ $EUID -ne 0 ]]; then
	printf '\n%s\n\n' 'You need to be root to run this script!'
	exit
fi

if [[ ! -d $1 || -z $2 ]]; then
	usage
elif [[ -f $2 ]]; then
	printf '\n%s\n\n' "\"${2}\" is a file!"
	exit
fi

if_dn=$(readlink -f "$1")
of_dn=$(readlink -f "$2")

declare session cp_log error_log used free
declare -A regex md5s

session="${RANDOM}-${RANDOM}"

cp_log="${of_dn}/hdd_dump_copied-${session}.txt"
error_log="${of_dn}/hdd_dump_errors-${session}.txt"

regex[du]='^([0-9]+)([[:blank:]]+)(.*)$'

mkdir -p "$of_dn" || exit

used=$(du --summarize --block-size=1 "$if_dn" | grep -Eo '^[0-9]+')
free=$(df --output=avail --block-size=1 "$of_dn" | tail -n +2 | tr -d '[:blank:]')

if [[ $used -gt $free ]]; then
	diff=$(( used - free ))

	cat <<USED

Not enough free space in:
${of_dn}

Difference is ${diff} bytes.

USED

	exit
fi

# The 'md5copy' function checks the MD5 hash of the input file, and
# tries to copy the file. It will try 5 times in total, both for getting
# the MD5 hash, and for copying the file, sleeping 10 seconds between
# each try.
md5copy () {
	if_tmp="$1"
	of_tmp="$2"

	declare md5_if exit_status

	for n in {1..5}; do
		md5_if=$(md5sum -b "$if_tmp" 2>&-)

		exit_status="$?"

		md5_if="${md5_if%% *}"

		if [[ $exit_status -eq 0 ]]; then
			if [[ ${md5s[${md5_if}]} -eq 1 ]]; then
				return
			fi
		else
			if [[ $n -eq 5 ]]; then
				printf '%s\n' "$if_tmp" >> "$error_log"

				return
			fi

			sleep 1
		fi
	done

	md5s["${md5_if}"]=1

	printf '%s' "copying: ${if_tmp}... "

	for n in {1..5}; do
		cp -p "$if_tmp" "$of_tmp" 2>&-

		exit_status="$?"

		if [[ $exit_status -eq 0 ]]; then
			printf '%s\n' 'done'
			printf '%s\n' "$if_tmp" >> "$cp_log"

			return
		else
			if [[ $n -eq 5 ]]; then
				printf '%s\n' 'error'
				printf '%s\n' "$if_tmp" >> "$error_log"

				if [[ -f $of_tmp ]]; then
					rm -f "$of_tmp" 2>&-
				fi

				return
			fi

			sleep 1
		fi
	done
}

touch "$cp_log" "$error_log"

mapfile -d'/' -t dn_parts <<<"$if_dn"
dn_parts[-1]="${dn_parts[-1]%$'\n'}"
start="${#dn_parts[@]}"

mapfile -t files < <(find "$if_dn" -type f -exec du -b {} + 2>&- | sort -n | sed -E "s/${regex[du]}/\3/")

for (( i = 0; i < ${#files[@]}; i++ )); do
	if="${files[${i}]}"

# Removes the directory name from the beginning of the string. Creating
# the basename this way because it's more safe than using regex:es, if
# the string contains weird characters (that are interpreted as part of
# the regex).
	mapfile -d'/' -t fn_parts <<<"$if"
	fn_parts[-1]="${fn_parts[-1]%$'\n'}"
	stop=$(( (${#fn_parts[@]} - ${#dn_parts[@]}) - 1 ))
	dn=$(printf '/%s' "${fn_parts[@]:${start}:${stop}}")
	dn="${dn:1}"
	bn="${fn_parts[-1]}"

	dn="${of_dn}/${dn}"
	of="${dn}/${bn}"

	mkdir -p "$dn" || exit

	if [[ ! -f $of ]]; then
		md5copy "$if" "$of"
	fi
done
