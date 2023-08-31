#!/bin/bash

# This script is a launcher for Rise of the Triad: Dark War (DOOM mod)
# for GZDoom.

# https://www.moddb.com/mods/return-of-the-triad

declare gzdoom_cfg rott_dn
declare doom_wad doom2_wad iwad wad

# Change the path variables below, to point to the correct directories
# for:
# * GZDoom configuration directory
# * Rise of the Triad: Dark War PK3 file directory
gzdoom_cfg="${HOME}/.var/app/org.zdoom.GZDoom/.config/gzdoom"
rott_dn="${gzdoom_cfg}/rott"

# * The Ultimate DOOM WAD
# * DOOM 2 WAD
# * Fake IWAD
# * Rise of the Triad: Dark War WAD
doom_wad="${gzdoom_cfg}/doom.wad"
doom2_wad="${gzdoom_cfg}/doom2.wad"
iwad="${rott_dn}/fakeiwad.wad"
wad="${rott_dn}/rott_tc_full.pk3"

# Creates a function, called 'gzdoom', which will run the GZDoom
# Flatpak (with arguments).
gzdoom () {
	flatpak run org.zdoom.GZDoom "$@"
}

gzdoom -iwad "$doom_wad" -file "$wad" -noautoload
