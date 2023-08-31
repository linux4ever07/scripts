#!/bin/bash

# This script is a launcher for Laz Rojas' WolfenDoom (DOOM 2 mod) for
# GZDoom.

# http://lazrojas.com/wolfendoom/index2.html
# https://forum.zdoom.org/viewtopic.php?t=48518

# File mirrors:

# https://www.dropbox.com/s/ws5xmhnncot3950/wolf4zdoom_v132.zip?dl=1
# https://mega.nz/#F!AFxnRCyZ!Ce648WN0JYI8jVWtZ_p89A
# https://ufile.io/c53dwjdf

declare gzdoom_cfg wolf_dn
declare doom_wad doom2_wad wad
declare -a wolf_wads
declare -a wolf_info
declare -A regex

# Change the path variables below, to point to the correct directories
# for:
# * GZDoom configuration directory
# * WolfenDoom PK3 files directory
gzdoom_cfg="${HOME}/.var/app/org.zdoom.GZDoom/.config/gzdoom"
wolf_dn="${gzdoom_cfg}/wolfendoom"

# * The Ultimate DOOM WAD
# * DOOM 2 WAD
doom_wad="${gzdoom_cfg}/doom.wad"
doom2_wad="${gzdoom_cfg}/doom2.wad"

regex[num]='^[0-9]+$'

cd "$wolf_dn"

# Creates a function, called 'gzdoom', which will run the GZDoom
# Flatpak (with arguments).
gzdoom () {
	flatpak run org.zdoom.GZDoom "$@"
}

# Laz Rojas WADs.
wolf_wads[0]='astrostein.pk3'
wolf_wads[1]='astrostein2.pk3'
wolf_wads[2]='astrostein3.pk3'
wolf_wads[3]='totenhaus.pk3'
wolf_wads[4]='halten.pk3'
wolf_wads[5]='arcticwolf1.pk3'
wolf_wads[6]='arcticwolf2.pk3'
wolf_wads[7]='eisenmann.pk3'
wolf_wads[8]='rheingold1.pk3'
wolf_wads[9]='rheingold2.pk3'
wolf_wads[10]='portal.pk3'
wolf_wads[11]='treasure.pk3'
wolf_wads[12]='wolfen_2nd.pk3'
wolf_wads[13]='wolfen_orig.pk3'
wolf_wads[14]='wolfen_noct.pk3'
wolf_wads[15]='wolfen_sod.pk3'

# Caleb26 Spear of Destiny WADs.
wolf_wads[16]='sod_revisited.pk3'
wolf_wads[17]='sod_lost.pk3'

# Laz Rojas WADs.
wolf_info[0]='Astrostein Trilogy 1'
wolf_info[1]='Astrostein Trilogy 2'
wolf_info[2]='Astrostein Trilogy 3'
wolf_info[3]='Escape from Totenhaus'
wolf_info[4]='Halten Sie!'
wolf_info[5]='Operation Arctic Wolf Pt. 1'
wolf_info[6]='Operation Arctic Wolf Pt. 2'
wolf_info[7]='Operation Eisenmann'
wolf_info[8]='Operation Rheingold Ep. 1'
wolf_info[9]='Operation Rheingold Ep. 2'
wolf_info[10]='The Portal'
wolf_info[11]='Treasure Hunt'
wolf_info[12]='WolfenDoom: Second Encounter'
wolf_info[13]='WolfenDoom: Original Missions'
wolf_info[14]='WolfenDoom: Nocturnal Missions'
wolf_info[15]='WolfenDoom: Spear of Destiny'

# Caleb26 Spear of Destiny WADs.
wolf_info[16]='Spear Revisited'
wolf_info[17]='SoD: The Lost Episodes'

while [[ 1 ]]; do
	printf '\n%s\n\n' '*** CHOOSE WAD ***'

	for (( i = 0; i < ${#wolf_wads[@]}; i++ )); do
		printf '%s) %s\n' "$i" "${wolf_info[${i}]}"
	done

	printf '\n'

	read -p '>'

	if [[ ! $REPLY =~ ${regex[num]} ]]; then
		continue
	fi

	wad="${wolf_wads[${REPLY}]}"

	if [[ -z $wad ]]; then
		continue
	fi

	gzdoom -iwad "$doom2_wad" -file "$wad" -noautoload

	break
done
