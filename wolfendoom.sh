#!/bin/bash

# This script is a launcher for Laz Rojas' WolfenDoom (DOOM 2 mod) for
# GZDoom.

# http://lazrojas.com/wolfendoom/index2.html
# https://forum.zdoom.org/viewtopic.php?t=48518

# File mirrors:

# https://www.dropbox.com/s/ws5xmhnncot3950/wolf4zdoom_v132.zip?dl=1
# https://mega.nz/#F!AFxnRCyZ!Ce648WN0JYI8jVWtZ_p89A
# https://ufile.io/c53dwjdf

declare gzdoom_cfg doom2_wad wolf_dn
declare -a wolfendoom_wads
declare -a wolfendoom_info
declare -A regex

# Change the path variables below, to point to the correct directories
# for:
# * GZDoom configuration directory
# * DOOM 2 WAD directory
# * WolfenDoom PK3 files directory
gzdoom_cfg="${HOME}/.var/app/org.zdoom.GZDoom/.config/gzdoom"
doom2_wad="${gzdoom_cfg}/doom2.wad"
wolf_dn="${gzdoom_cfg}/wolfendoom"

regex[num]='^[0-9]+$'

cd "$wolf_dn"

# Creates a function, called 'gzdoom', which will run the GZDoom
# Flatpak (with arguments).
gzdoom () {
    flatpak run org.zdoom.GZDoom "$@"
}

# Laz Rojas WADs.
wolfendoom_wads[0]='astrostein.pk3'
wolfendoom_wads[1]='astrostein2.pk3'
wolfendoom_wads[2]='astrostein3.pk3'
wolfendoom_wads[3]='totenhaus.pk3'
wolfendoom_wads[4]='halten.pk3'
wolfendoom_wads[5]='arcticwolf1.pk3'
wolfendoom_wads[6]='arcticwolf2.pk3'
wolfendoom_wads[7]='eisenmann.pk3'
wolfendoom_wads[8]='rheingold1.pk3'
wolfendoom_wads[9]='rheingold2.pk3'
wolfendoom_wads[10]='portal.pk3'
wolfendoom_wads[11]='treasure.pk3'
wolfendoom_wads[12]='wolfen_2nd.pk3'
wolfendoom_wads[13]='wolfen_orig.pk3'
wolfendoom_wads[14]='wolfen_noct.pk3'
wolfendoom_wads[15]='wolfen_sod.pk3'

# Caleb26 Spear of Destiny WADs.
wolfendoom_wads[16]='sod_revisited.pk3'
wolfendoom_wads[17]='sod_lost.pk3'

# Laz Rojas WADs.
wolfendoom_info[0]='Astrostein Trilogy 1'
wolfendoom_info[1]='Astrostein Trilogy 2'
wolfendoom_info[2]='Astrostein Trilogy 3'
wolfendoom_info[3]='Escape from Totenhaus'
wolfendoom_info[4]='Halten Sie!'
wolfendoom_info[5]='Operation Arctic Wolf Pt. 1'
wolfendoom_info[6]='Operation Arctic Wolf Pt. 2'
wolfendoom_info[7]='Operation Eisenmann'
wolfendoom_info[8]='Operation Rheingold Ep. 1'
wolfendoom_info[9]='Operation Rheingold Ep. 2'
wolfendoom_info[10]='The Portal'
wolfendoom_info[11]='Treasure Hunt'
wolfendoom_info[12]='WolfenDoom: Second Encounter'
wolfendoom_info[13]='WolfenDoom: Original Missions'
wolfendoom_info[14]='WolfenDoom: Nocturnal Missions'
wolfendoom_info[15]='WolfenDoom: Spear of Destiny'

# Caleb26 Spear of Destiny WADs.
wolfendoom_info[16]='Spear Revisited'
wolfendoom_info[17]='SoD: The Lost Episodes'

while [[ 1 ]]; do
	printf '\n%s\n\n' '*** CHOOSE WAD ***'

	for (( i = 0; i < ${#wolfendoom_wads[@]}; i++ )); do
		printf '%s) %s\n' "$i" "${wolfendoom_info[${i}]}"
	done

	printf '\n'

	read -p '>'

	if [[ ! $REPLY =~ ${regex[num]} ]]; then
		continue
	fi

	wad="${wolfendoom_wads[${REPLY}]}"

	if [[ -z $wad ]]; then
		continue
	fi

	gzdoom -iwad "$doom2_wad" -file "$wad" -noautoload

	break
done
