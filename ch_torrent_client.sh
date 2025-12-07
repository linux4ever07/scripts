#!/bin/bash

# This is just a simple script to change the default BitTorrent client
# in GNOME. It allows the user to search for the name of the torrent
# client that they want, and select it from a menu.

# xdg-mime query default x-scheme-handler/magnet
# xdg-mime query default application/x-bittorrent

set -eo pipefail

# Creates a function, called 'usage', which will print usage
# instructions and then quit.
usage () {
	printf '\n%s\n\n' "Usage: $(basename "$0") [name]"
	exit
}

if [[ $# -ne 1 ]]; then
	usage
fi

declare name_in name_out
declare -a files

name_in="$1"

mapfile -t files < <(find '/usr/share/applications/' -mindepth 1 -maxdepth 1 -type f -iname "*${name_in}*.desktop" -exec basename -a {} + 2>&-)

select name_out in "${files[@]}"; do
	break
done

if [[ -z $name_out ]]; then
	exit
fi

xdg-mime default "$name_out" x-scheme-handler/magnet
xdg-mime default "$name_out" application/x-bittorrent
