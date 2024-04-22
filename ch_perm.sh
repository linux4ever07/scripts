#!/bin/bash

# This script recursively changes the owner (and group) of input files /
# directories, to either the current user or root. It also changes read
# / write permissions to match. In the case of root, all input files
# and directories are write-protected.

# Creates a function, called 'usage', which will print usage
# instructions and then quit.
usage () {
	printf '\n%s\n\n' "Usage: $(basename "$0") [user|root] [file / directory]"
	exit
}

# Creates a function, called 'ch_perm', which will figure out if the
# name is a file or a directory, and change the permissions accordingly.
ch_perm () {
	declare dn
	declare -a dirs

	sudo chown -v -R "${owner}:${owner}" "$1"

	if [[ $owner == "$USER" ]]; then
		sudo chmod -v -R +rw "$1"
	fi

	if [[ $owner == 'root' ]]; then
		sudo chmod -v -R ugo-w "$1"
	fi

	if [[ -f $1 ]]; then
		return
	fi

	mapfile -t dirs < <(sudo find "$1" -type d 2>&-)

	for (( i = 0; i < ${#dirs[@]}; i++ )); do
		dn="${dirs[${i}]}"
		sudo chmod -v ugo+x "$dn"
	done
}

declare owner fn

case "$1" in
	'user')
		owner="$USER"
	;;
	'root')
		owner='root'
	;;
	*)
		usage
	;;
esac

shift

if [[ $# -eq 0 ]]; then
	usage
fi

while [[ $# -gt 0 ]]; do
	fn=$(readlink -f "$1")

	if [[ ! -f $fn && ! -d $fn ]]; then
		usage
	fi

	ch_perm "$fn"

	shift
done
