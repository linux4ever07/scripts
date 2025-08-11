#!/bin/bash

# This script slowly and gradually lowers the volume until it's equal to
# 0%. Although, any target volume can be set using the $volume[target]
# variable. The script takes 1 hour (3600 * 1 seconds) all in all, to
# completely lower the volume to the target volume.

# I'm using this script to automatically lower the volume when I fall
# asleep to watching a movie or YouTube.

# https://gitlab.freedesktop.org/pipewire/pipewire/-/wikis/Migrate-PulseAudio

# FYI:

# The volume seems to behave differently depending on the connection
# type of speakers (analog or digital). If the connection is analog then
# the volume level in PipeWire acts independently of the desktop
# environment, but this isn't the case when using a digital S/PDIF
# connection. The 'reset_volume' function is for when the volume of the
# DE and PipeWire is independent. Otherwise that function doesn't need
# to be run, and the line that runs it can be commented out.

# This is the current behavior in GNOME at least, but it might be
# different in other DEs or WMs.

# If the user wants to arbitrarily delay the lowering of volume, they
# can do this:

# sleep 1h; lower_volume_pw.sh

declare fn pw_id interval unit
declare -a channels interval_out
declare -A regex volume cfg

regex[blank1]='^[[:blank:]]*(.*)[[:blank:]]*$'
regex[blank2]='[[:blank:]]+'
regex[id]='^id ([0-9]+),'
regex[node]='^node\.description = \"(.+)\"'
regex[class]='^media\.class = \"(.+)\"'
regex[sink]='^Audio\/Sink$'
regex[volume1]='^\"channelVolumes\": \[ (.+) \],'
regex[volume2]='^([0-9]+\.[0-9]+)(, ){0,1}(.*)$'
regex[volume3]='^([0-9]+)\.([0-9]+)$'
regex[zero]='^0+([0-9]+)$'
regex[split]='^([0-9]+)([0-9]{6})$'
regex[cfg]='^(.+) = (.+)$'

volume[max]=1000000
volume[min]=0
volume[target]=0

interval=1
unit=3600

fn="${HOME}/lower_volume_pw.cfg"

# Creates a function, called 'read_cfg', which reads the configuration
# file, if it exists. Right now, the file only has 1 value (node), but
# that might change in future versions of the script.
read_cfg () {
	declare line
	declare -a lines

	if [[ ! -f $fn ]]; then
		return
	fi

	mapfile -t lines < <(tr -d '\r' <"$fn")

	for (( i = 0; i < ${#lines[@]}; i++ )); do
		line="${lines[${i}]}"

		if [[ ! $line =~ ${regex[cfg]} ]]; then
			continue
		fi

		cfg["${BASH_REMATCH[1]}"]="${BASH_REMATCH[2]}"
	done
}

# Creates a function, called 'get_id', which decides the audio output to
# use, based on user selection or the existence of a configuration file.
get_id () {
	declare pw_node n line
	declare -a pw_info
	declare -A pw_parsed nodes

	n=-1

	match_node () {
		declare pw_id_tmp pw_node_tmp

		for pw_id_tmp in "${!nodes[@]}"; do
			pw_node_tmp="${nodes[${pw_id_tmp}]}"

			if [[ $pw_node_tmp != "$pw_node" ]]; then
				continue
			fi

			pw_id="$pw_id_tmp"

			break
		done
	}

	mapfile -t pw_info < <(pw-cli ls Node | sed -E -e "s/${regex[blank1]}/\1/" -e "s/${regex[blank2]}/ /g")

# Parses the output from 'pw-cli'.
	for (( i = 0; i < ${#pw_info[@]}; i++ )); do
		line="${pw_info[${i}]}"

		if [[ $line =~ ${regex[id]} ]]; then
			(( n += 1 ))

			pw_parsed["${n},id"]="${BASH_REMATCH[1]}"

			continue
		fi

		if [[ $line =~ ${regex[node]} ]]; then
			pw_parsed["${n},node"]="${BASH_REMATCH[1]}"

			continue
		fi

		if [[ $line =~ ${regex[class]} ]]; then
			pw_parsed["${n},class"]="${BASH_REMATCH[1]}"

			continue
		fi
	done

	(( n += 1 ))

# Saves the ids and node names of every node that's an audio sink.
	for (( i = 0; i < n; i++ )); do
		if [[ ${pw_parsed[${i},class]} =~ ${regex[sink]} ]]; then
			nodes["${pw_parsed[${i},id]}"]="${pw_parsed[${i},node]}"
		fi
	done

	unset -v n

	pw_node="${cfg[node]}"

# If the configuration file exists, get the node name from that.
	if [[ -n $pw_node ]]; then
		match_node
	fi

# If the node name found in configuration file doesn't exist, clear
# the $pw_node variable so a new one can be created.
	if [[ -n $pw_id ]]; then
		printf '\n%s:\n%s\n\n' 'Using audio output found in' "$fn"
	else
# If there's no configuration file, then ask the user to select audio
# output. That will get written to the configuration file.
		printf '\n%s\n\n' 'Select your audio output:'

		select pw_node in "${nodes[@]}"; do
			match_node

			break
		done

		if [[ -n $pw_node ]]; then
			line="node = ${pw_node}"

			printf '%s\n\n' "$line" > "$fn"
			printf '\n%s:\n%s\n\n' 'Wrote selected audio output to' "$fn"
		fi
	fi

	if [[ -z $pw_id ]]; then
		printf '\n%s\n\n' 'Failed to get audio output ID!'

		exit
	fi
}

# Creates a function, called 'get_volume', which gets the current
# volume.
get_volume () {
	declare line
	declare -a pw_dump

	mapfile -t pw_dump < <(pw-dump "$pw_id" | sed -E -e "s/${regex[blank1]}/\1/" -e "s/${regex[blank2]}/ /g")

	for (( i = 0; i < ${#pw_dump[@]}; i++ )); do
		line="${pw_dump[${i}]}"

		if [[ ! $line =~ ${regex[volume1]} ]]; then
			continue
		fi

		line="${BASH_REMATCH[1]}"

		while [[ $line =~ ${regex[volume2]} ]]; do
			channels+=("${BASH_REMATCH[1]}")

			line="${BASH_REMATCH[3]}"
		done

		break
	done

	for (( i = 0; i < ${#channels[@]}; i++ )); do
		if [[ ! ${channels[${i}]} =~ ${regex[volume3]} ]]; then
			continue
		fi

		channels["${i}"]="${BASH_REMATCH[1]}${BASH_REMATCH[2]}"

		if [[ ${channels[${i}]} =~ ${regex[zero]} ]]; then
			channels["${i}"]="${BASH_REMATCH[1]}"
		fi
	done

	volume[in]="${channels[0]}"

	if [[ -z ${volume[in]} ]]; then
		printf '\n%s\n\n' 'Failed to get current volume!'

		exit
	fi

	volume[out]="${volume[in]}"
}

# Creates a function, called 'set_volume', which sets the volume.
set_volume () {
	declare mute_tmp volume_1 volume_2

	mute_tmp="$1"

	if [[ ${volume[out]} =~ ${regex[split]} ]]; then
		volume_1="${BASH_REMATCH[1]}"
		volume_2="${BASH_REMATCH[2]}"

		if [[ $volume_2 =~ ${regex[zero]} ]]; then
			volume_2="${BASH_REMATCH[1]}"
		fi
	else
		volume_1=0
		volume_2="${volume[out]}"
	fi

	volume[dec]=$(printf '%d.%06d' "$volume_1" "$volume_2")

	for (( z = 0; z < ${#channels[@]}; z++ )); do
		volume[list]+="${volume[dec]}, "
	done

	volume[list]="${volume[list]%, }"

	pw-cli s "$pw_id" Props "{ mute: ${mute_tmp}, channelVolumes: [ ${volume[list]} ] }" 1>&- 2>&-

	unset -v volume[dec] volume[list]
}

# Creates a function, called 'reset_volume', which resets the volume.
reset_volume () {
	volume[out]="${volume[min]}"
	set_volume 'false'

	until [[ ${volume[out]} -ge ${volume[max]} ]]; do
		sleep 0.1

		(( volume[out] += 100000 ))
		set_volume 'false'
	done
}

# Creates a function, called 'sleep_low', which sleeps and then lowers
# the volume.
sleep_low () {
	printf '  %-7s\r' "${volume[out]}"

	for (( i = 0; i < ${#interval_out[@]}; i++ )); do
		sleep "$interval"

		volume[out]="${interval_out[${i}]}"
		set_volume 'false'

		printf '  %-7s\r' "${volume[out]}"
	done
}

# Creates a function, called 'get_interval', which will get the exact
# number to decrease the volume by at each interval. Since Bash can't do
# floating-point arithmetic, this becomes slightly tricky. Keep in mind
# that Bash always rounds down, never up.
get_interval () {
	declare first last
	declare -a diff

# Calculates the difference between current volume and target volume.
	diff[0]=$(( (volume[out] - volume[target]) / unit ))
	diff[1]="${volume[out]}"

# Creates array elements representing the desired volume level at each
# point in time, by subtracting the difference between current volume
# and target volume.
	for (( i = 0; i < unit; i++ )); do
		(( diff[1] -= diff[0] ))
		interval_out["${i}"]="${diff[1]}"
	done

	if [[ ${diff[1]} -eq ${volume[target]} ]]; then
		return
	fi

	(( diff[1] -= volume[target] ))

	first=$(( ${#interval_out[@]} - diff[1] ))
	last=$(( ${#interval_out[@]} - 1 ))

# If there's still a remaining difference, go through the array in
# reverse, and subtract from each element until the difference is gone.
# This will distribute the difference evenly.
	for (( i = last; i >= first; i-- )); do
		(( interval_out[${i}] -= diff[1] ))
		(( diff[1] -= 1 ))
	done
}

# Reads the configuration file, if it exists.
read_cfg

# Gets the PipeWire id.
get_id

# Gets the volume.
get_volume

# We (re)set the original volume as full volume, cause otherwise the
# first lowering of volume is going to be much lower to the ears than
# the value set in PipeWire. The volume set in the desktop environment
# seems to be indpendent of the volume set in PipeWire, which might be
# what's causing this.
#reset_volume

# If volume is greater than target volume, then...
if [[ ${volume[out]} -gt ${volume[target]} ]]; then
# Gets the amount to lower the volume by at each interval.
	get_interval

# Lowers the volume.
	sleep_low

# Prints newline.
	printf '\n\n'
fi
