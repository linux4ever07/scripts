#!/bin/bash

# This script is meant to compare two directories, check MD5 hashes of
# all the files in both directories, to see which ones are identical and
# which aren't. The script also checks the number of files and will list
# potential missing files that exist in either directory, but not in the
# other.

# The script takes two arguments, both being directories.

set -eo pipefail

declare is_md5sum dir1 dir2 dir1_size dir2_size regex
declare dir1_files_elements dir1_dirs_elements dir2_files_elements dir2_dirs_elements
declare dir type key dir1_f dir2_f start bn bn_md5
declare dir1_files_missing_elements dir1_dirs_missing_elements
declare dir2_files_missing_elements dir2_dirs_missing_elements
declare md5s_mismatch_elements identical
declare dn_ref fn_ref elements_ref
declare -a dir1_files dir1_dirs dir2_files dir2_dirs var_list1 var_list2 var_list3 dn_parts fn_parts

# Checks if the user has 'md5sum' installed. This will probably not be
# the case for macOS or FreeBSD, and that's why we're checking. If such
# a user wants to run this script, he / she can just change the script
# to use 'md5' instead, and parse the output accordingly.
is_md5sum=$(command -v md5sum)

if [[ -z $is_md5sum ]]; then
	printf '\n%s\n\n' "This script needs 'md5sum' installed to run!"
	exit
fi

usage () {
	printf '\n%s\n\n' "Usage: $(basename "$0") [dir1] [dir2]"
	exit
}

# Checks if arguments are directories, and quits if they aren't.
if [[ ! -d $1 || ! -d $2  ]]; then
	usage
fi

# Gets absolute path of both directories.
dir1=$(readlink -f "$1")
dir2=$(readlink -f "$2")

# Gets the total size of both directories.
dir1_size=$(du -b -s "$dir1" | grep -Eo '^[0-9]+')
dir2_size=$(du -b -s "$dir2" | grep -Eo '^[0-9]+')

regex='([^ a-zA-Z0-9\.\-_ ])'

# Lists all the files and directories in both directories.
mapfile -t dir1_files < <(find "$dir1" -type f 2>&- | sed -E "s/${regex}/\\1/g")
mapfile -t dir1_dirs < <(find "$dir1" -mindepth 1 -type d -empty 2>&- | sed -E "s/${regex}/\\1/g")
mapfile -t dir2_files < <(find "$dir2" -type f 2>&- | sed -E "s/${regex}/\\1/g")
mapfile -t dir2_dirs < <(find "$dir2" -mindepth 1 -type d -empty 2>&- | sed -E "s/${regex}/\\1/g")

dir1_files_elements="${#dir1_files[@]}"
dir1_dirs_elements="${#dir1_dirs[@]}"
dir2_files_elements="${#dir2_files[@]}"
dir2_dirs_elements="${#dir2_dirs[@]}"

# Declares some hashes that will be used to compare the two directories.
var_list1=(dir1_files_hash dir1_dirs_hash dir2_files_hash dir2_dirs_hash dir1_md5s_hash dir2_md5s_hash)
var_list2=(dn_parts fn_parts start bn bn_md5)

declare -A "${var_list1[@]}"

# Converts the basename of all the files (in both directories) into MD5
# hashes, to be more easily processed later in the script.
for dir in dir1 dir2; do
	dn_ref="$dir"

	mapfile -d'/' -t dn_parts <<<"${!dn_ref}"
	dn_parts[-1]="${dn_parts[-1]%$'\n'}"
	start="${#dn_parts[@]}"

	for type in files dirs; do
		elements_ref="${dir}_${type}_elements"

		for (( i = 0; i < ${!elements_ref}; i++ )); do
			fn_ref="${dir}_${type}[${i}]"

# Removes the directory name from the beginning of the string. Creating
# the basename this way because it's more safe than using regex:es, if
# the string contains weird characters (that are interpreted as part of
# the regex).
			mapfile -d'/' -t fn_parts <<<"${!fn_ref}"
			fn_parts[-1]="${fn_parts[-1]%$'\n'}"
			bn=$(printf '/%s' "${fn_parts[@]:${start}}")
			bn="${bn:1}"

# Okay, we're done messing with the string now. Now to create the MD5
# hash.
			bn_md5=$(md5sum -b <<<"$bn")
			bn_md5="${bn_md5%% *}"
			eval "${dir}"_"${type}"_hash["${bn_md5}"]=\""${bn}"\"
		done

		unset -v "${dir}_type"
	done
done

unset -v "${var_list2[@]}"

# Generates an MD5 hash of all the basenames that exist in both
# directories. This is faster than checking the MD5 hash of *all* the
# files. We only need to check the file names that exist in both
# directories.
for key in "${!dir1_files_hash[@]}"; do
	dir1_f="${dir1}/${dir1_files_hash[${key}]}"

	if [[ ${dir2_files_hash[${key}]} ]]; then
		dir2_f="${dir2}/${dir2_files_hash[${key}]}"

		dir1_md5s_hash["${key}"]=$(md5sum -b "$dir1_f")
		dir1_md5s_hash["${key}"]="${dir1_md5s_hash[${key}]%% *}"
		dir2_md5s_hash["${key}"]=$(md5sum -b "$dir2_f")
		dir2_md5s_hash["${key}"]="${dir2_md5s_hash[${key}]%% *}"
	fi
done

# Compares the two directories to see if files or directories are
# missing.
var_list3=(dir1_files_missing dir1_dirs_missing dir2_files_missing dir2_dirs_missing md5s_mismatch)

declare -a "${var_list3[@]}"

# Files
for key in "${!dir1_files_hash[@]}"; do
	if [[ -z ${dir2_files_hash[${key}]} ]]; then
		dir2_files_missing+=("${dir1_files_hash[${key}]}")
	elif [[ ${dir1_md5s_hash[${key}]} != "${dir2_md5s_hash[${key}]}" ]]; then
		md5s_mismatch+=("${dir1_files_hash[${key}]}")
	fi
done

for key in "${!dir2_files_hash[@]}"; do
	if [[ -z ${dir1_files_hash[${key}]} ]]; then
		dir1_files_missing+=("${dir2_files_hash[${key}]}")
	fi
done

# Directories
for key in "${!dir1_dirs_hash[@]}"; do
	if [[ -z ${dir2_dirs_hash[${key}]} ]]; then
		dir2_dirs_missing+=("${dir1_dirs_hash[${key}]}")
	fi
done

for key in "${!dir2_dirs_hash[@]}"; do
	if [[ -z ${dir1_dirs_hash[${key}]} ]]; then
		dir1_dirs_missing+=("${dir2_dirs_hash[${key}]}")
	fi
done

unset -v "${var_list1[@]}"

dir1_files_missing_elements="${#dir1_files_missing[@]}"
dir1_dirs_missing_elements="${#dir1_dirs_missing[@]}"
dir2_files_missing_elements="${#dir2_files_missing[@]}"
dir2_dirs_missing_elements="${#dir2_dirs_missing[@]}"
md5s_mismatch_elements="${#md5s_mismatch[@]}"

identical='1'

# Prints the result.
print_list () {
	fn_ref="${type}[@]"
	printf '%s\n' "${!fn_ref}" | sort

	unset -v "$type"

	printf '\n'
}

for type in "${var_list3[@]}"; do
	elements_ref="${type}_elements"

	if [[ ${!elements_ref} -gt 0 ]]; then
		identical='0'
	else
		continue
	fi

	printf '\n'

	case $type in
		'dir1_files_missing')
			printf '%s\n' "*** 1:${dir1}"
			printf '%s\n\n' "The files below are missing:"

			print_list
		;;
		'dir1_dirs_missing')
			printf '%s\n' "*** 1:${dir1}"
			printf '%s\n\n' "The directories below are missing:"

			print_list
		;;
		'dir2_files_missing')
			printf '%s\n' "*** 2:${dir2}"
			printf '%s\n\n' "The files below are missing:"

			print_list
		;;
		'dir2_dirs_missing')
			printf '%s\n' "*** 2:${dir2}"
			printf '%s\n\n' "The directories below are missing:"

			print_list
		;;
		'md5s_mismatch')
			printf '%s\n' "*** 1:${dir1}"
			printf '%s\n' "*** 2:${dir2}"
			printf '%s\n\n' "MD5 hash mismatch:"

			print_list
		;;
	esac
done

# If directories are identical, the code above will have printed
# nothing, so we print a message saying that the directories are
# identical.
if [[ $identical -eq 1 ]]; then
	cat <<P_IDENT

*** 1:${dir1}
*** 2:${dir2}
The directories are identical!

P_IDENT
fi

# Prints size.
cat <<P_SUM

*** 1:${dir1}
*** 2:${dir2}
Summary:

1:${dir1_size} bytes
2:${dir2_size} bytes

1:${dir1_files_elements} files
2:${dir2_files_elements} files

P_SUM
