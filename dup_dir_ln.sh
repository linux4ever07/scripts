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

usage () {
	echo -e "Usage: $(basename "$0") [in_dir] [out_dir]\n"
	exit
}

# If the script isn't run with sudo / root privileges, then quit.
if [[ $(whoami) != root ]]; then
	echo -e "You need to be root to run this script!\n"
	exit
fi

if [[ ! -d $1 || -z $2 ]]; then
	usage
elif [[ -d $2 || -f $2 ]]; then
	echo -e "\"${2}\" already exists!\n"
	exit
fi

in_dir=$(readlink -f "$1")
out_dir="$2"

pause_msg="You're about to recursively symlink:
\"${in_dir}\"

to

\"${out_dir}\"

To continue, press Enter. To abort, press Ctrl+C."

read -p "$pause_msg"

mapfile -t dirs < <(find "$in_dir" -type d -iname "*" | tail -n +2)
mapfile -t files < <(find "$in_dir" -type f -iname "*")

# Directories.

mkdir -p "$2"

for (( i = 0; i < ${#dirs[@]}; i++ )); do
	if="${dirs[${i}]}"

# Removes the directory name from the beginning of the string. Creating
# the basename this way because it's more safe than using regex:es, if
# the string contains weird characters (that are interpreted as part of
# the regex).
	mapfile -d'/' -t path_parts <<<"${in_dir}"
	start=$(( ${#path_parts[@]} + 1 ))
	bn=$(cut -d'/' -f${start}- <<<"${if}")

	of="${2}/${bn}"

	mkdir -p "$of"
done

# Files.

for (( i = 0; i < ${#files[@]}; i++ )); do
	if="${files[${i}]}"

# Removes the directory name from the beginning of the string. Creating
# the basename this way because it's more safe than using regex:es, if
# the string contains weird characters (that are interpreted as part of
# the regex).
	mapfile -d'/' -t path_parts <<<"${in_dir}"
	start=$(( ${#path_parts[@]} + 1 ))
	bn=$(cut -d'/' -f${start}- <<<"${if}")

	of="${2}/${bn}"

	ln -s "$if" "$of"
done

# Change the permissions of the output directory.

chown -R root:root "$2"
chmod -R +r "$2"
