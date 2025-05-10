#!/bin/bash

# Add symbolic links to my old drives, pointing to the new directory.
# This is so my torrent clients can access the torrents that were
# already loaded since before I swapped out some old drives.

# If you want to do something similar, just change / add / remove array
# elements as needed.

declare drive_in drive_out
declare -a drives_in drives_out

drives_in[0]='5c42d46c-30d6-4b43-a784-30a8328da5ae'
drives_in[1]='f61840d6-9ba6-4cf8-ad6f-5c97c8c58b18'
drives_in[2]='a73f90cd-c719-4093-92ac-f234920312f5'
drives_in[3]='7b12e3a8-8802-4e3e-b782-fe94e5c57137'

drives_out[0]="/home/${USER}/Downloads"
drives_out[1]="/home/${USER}/Downloads"
drives_out[2]="/run/media/${USER}/2c5518a5-5311-4a7d-8356-206fecd9f13f"
drives_out[3]="/run/media/${USER}/2c5518a5-5311-4a7d-8356-206fecd9f13f"

cd "/run/media/${USER}"

for (( i = 0; i < ${#drives_in[@]}; i++ )); do
	drive_in="${drives_in[${i}]}"
	drive_out="${drives_out[${i}]}"

	if [[ ! -L $drive_in ]]; then
		sudo ln -s "$drive_out" "$drive_in"
		sudo chown "${USER}:${USER}" "$drive_in"
	fi
done
