#!/bin/bash

# This script is meant to handle drives that have been connected to an
# NVIDIA SHIELD. The SHIELD creates 2 special directories on drives that
# have been connected to it. Those directories sometimes cannot be
# accessed in Linux. They can't be read, moved, copied or deleted.

# The script is specifically meant to prepare a drive so its content can
# be copied to another drive. To avoid errors when using 'cp -rp', we
# need to move everything to a sub-directory, except the 2 special
# SHIELD directories. And then copy the content of that sub-directory to
# the destination drive. However, the script does not do the copying
# step. That will have to be done manually.

set -eo pipefail

declare fn_ignore session switch
declare -a dirs files ignore
declare -A if of

# Creates a function, called 'usage', which will print usage
# instructions and then quit.
usage () {
	printf '\n%s\n\n' "Usage: $(basename "$0") [directory] [...]"
	exit
}

if [[ $# -eq 0 ]]; then
	usage
fi

while [[ $# -gt 0 ]]; do
	if [[ -d $1 ]]; then
		dirs+=("$(readlink -f $1)")
	else
		usage
	fi

	shift
done

# The 'ignore' array contains the names of the special SHIELD
# directories.
ignore=('NVIDIA_SHIELD' 'LOST.DIR')

# Loop through directories given as arguments to the script.
for (( i = 0; i < ${#dirs[@]}; i++ )); do
	if[dn]="${dirs[${i}]}"
	session="${RANDOM}-${RANDOM}"
	of[dn]="${if[dn]}/${session}"

# Change into the directory.
	cd "${if[dn]}"

# List everything in the current directory, including hidden files.
	mapfile -t files < <(ls -1A)

# Create destination sub-directory.
	mkdir -p "${of[dn]}"

# Loop through files and sub-directories in the current directory.
	for (( j = 0; j < ${#files[@]}; j++ )); do
		if[fn]="${files[${j}]}"
		switch=0

# If current file name matches any of the special SHIELD directories,
# ignore it.
		for fn_ignore in "${ignore[@]}"; do
			if [[ ${if[fn]} == "$fn_ignore" ]]; then
				switch=1
				break
			fi
		done

		if [[ $switch -eq 1 ]]; then
			continue
		fi

# Move the current file / directory to destination sub-directory,
# without overwriting.
		mv -n "${if[fn]}" "${of[dn]}"
	done
done
