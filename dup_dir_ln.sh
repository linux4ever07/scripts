#!/bin/bash

# This script creates a duplicate of the directory specified, by
# recursively re-creating the sub-directories and then creating symbolic
# links for all the files.

# The script takes two arguments, first being input directory, and
# second being the name of the output directory.

# This script was originally created to allow me to seed two slightly
# different versions of the same torrent at once. I removed some files
# and added some files in the new version of the torrent, and the rest
# of the files are symlinks.

# The permissions of the output directory will be root for owner, and
# group, with only read permissions for everyone else. Permissions only
# affect the created sub-directories in the output directory, not the
# symlinks.

set -eo pipefail

# Creates a function, called 'usage', which will print usage
# instructions and then quit.
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
elif [[ -e $2 ]]; then
	printf '\n%s\n\n' "\"${2}\" already exists!"
	exit
fi

declare pause_msg start stop
declare -a files dn_parts fn_parts
declare -A if of

if[dn]=$(readlink -f "$1")
of[dn]=$(readlink -f "$2")

pause_msg="
You're about to recursively symlink:
  \"${if[dn]}\"

To:
  \"${of[dn]}\"

Are you sure? [y/n]: "

read -p "$pause_msg"

if [[ $REPLY != 'y' ]]; then
	exit
fi

mapfile -d'/' -t dn_parts <<<"${if[dn]}"
dn_parts[-1]="${dn_parts[-1]%$'\n'}"
start="${#dn_parts[@]}"

mapfile -t files < <(find "${if[dn]}" -type f 2>&-)

for (( i = 0; i < ${#files[@]}; i++ )); do
	if[fn]="${files[${i}]}"

# Removes the directory name from the beginning of the string. Creating
# the basename this way because it's more safe than using regex:es, if
# the string contains weird characters (that are interpreted as part of
# the regex).
	mapfile -d'/' -t fn_parts <<<"${if[fn]}"
	fn_parts[-1]="${fn_parts[-1]%$'\n'}"
	stop=$(( (${#fn_parts[@]} - ${#dn_parts[@]}) - 1 ))
	of[dn_tmp]=$(printf '/%s' "${fn_parts[@]:${start}:${stop}}")
	of[dn_tmp]="${of[dn_tmp]:1}"
	of[bn]="${fn_parts[-1]}"

	of[dn_tmp]="${of[dn]}/${of[dn_tmp]}"
	of[fn]="${of[dn_tmp]}/${of[bn]}"

	mkdir -p "${of[dn_tmp]}"
	ln -s "${if[fn]}" "${of[fn]}"
done

# Changes the owner and permissions of the output directory.
chown -R root:root "${of[dn]}"
chmod -R +r "${of[dn]}"
