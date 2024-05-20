#!/bin/bash

# This script slowly and gradually lowers the volume until it's equal to
# 0%. Although, any target volume can be set using the $volume[target]
# variable. The script takes 1 hour (360 * 10 seconds) all in all, to
# completely lower the volume to the target volume.

# I'm using this script to automatically lower the volume when I fall
# asleep to watching a movie or YouTube.

# https://gitlab.freedesktop.org/pipewire/pipewire/-/wikis/Migrate-PulseAudio

declare cfg_fn pw_id interval unit spin_pid n
declare -a count
declare -A regex volume

regex[blank1]='^[[:blank:]]*(.*)[[:blank:]]*$'
regex[blank2]='[[:blank:]]+'
regex[id]='^id ([0-9]+),'
regex[node]='^node\.description = \"(.*)\"'
regex[class]='^media\.class = \"(.*)\"'
regex[sink]='^Audio\/Sink$'
regex[volume]='^\"channelVolumes\": \[ ([0-9]+\.[0-9]+), [0-9]+\.[0-9]+ \],'
regex[zero]='^0+([0-9]+)$'
regex[split]='^([0-9]+)([0-9]{6})$'
regex[cfg_node]='^node = (.*)$'

volume[full]=1000000
volume[no]=0
volume[target]=0

cfg_fn="${HOME}/lower_volume_pw.cfg"

interval=10
unit=354

count=(0 0 0)

# Creates a function, called 'get_id', which decides the audio output to
# use, based on user selection or the existence of a configuration file.
get_id () {
	declare pw_node pw_node_tmp n line
	declare -a pw_info lines
	declare -A pw_parsed nodes

	match_node () {
		declare pw_id_tmp

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

# Parse the output from 'pw-cli'...
	for (( i = 0; i < ${#pw_info[@]}; i++ )); do
		line="${pw_info[${i}]}"

		if [[ $line =~ ${regex[id]} ]]; then
			if [[ -z $n ]]; then
				n=0
			else
				(( n += 1 ))
			fi

			pw_parsed["${n},id"]="${BASH_REMATCH[1]}"
		fi

		if [[ $line =~ ${regex[node]} ]]; then
			pw_parsed["${n},node"]="${BASH_REMATCH[1]}"
		fi

		if [[ $line =~ ${regex[class]} ]]; then
			pw_parsed["${n},class"]="${BASH_REMATCH[1]}"
		fi
	done

	(( n += 1 ))

# Save the ids and node names of every node that's an audio sink.
	for (( i = 0; i < n; i++ )); do
		if [[ ${pw_parsed[${i},class]} =~ ${regex[sink]} ]]; then
			nodes["${pw_parsed[${i},id]}"]="${pw_parsed[${i},node]}"
		fi
	done

	unset -v n

# If the configuration file exists, get the node name from that.
	if [[ -f $cfg_fn ]]; then
		printf '\n%s: %s\n\n' 'Using audio output found in' "$cfg_fn"

		mapfile -t lines <"$cfg_fn"

		for (( i = 0; i < ${#lines[@]}; i++ )); do
			line="${lines[${i}]}"

			if [[ ! $line =~ ${regex[cfg_node]} ]]; then
				continue
			fi

			pw_node="${BASH_REMATCH[1]}"

			break
		done

		if [[ -n $pw_node ]]; then
			match_node
		fi

# If the node name found in configuration file doesn't exist, clear
# the $pw_node variable so a new one can be created.
		if [[ -z $pw_id ]]; then
			unset -v pw_node
		fi
	fi

# If there's no configuration file, then ask the user to select audio
# output. That will get written to the configuration file.
	if [[ -z $pw_node ]]; then
		printf '\n%s\n\n' 'Select your audio output:'

		select pw_node in "${nodes[@]}"; do
			match_node

			break
		done

		if [[ -n $pw_node ]]; then
			line="node = ${pw_node}"

			printf '%s\n\n' "$line" > "$cfg_fn"
			printf '\n%s: %s\n\n' 'Wrote selected audio output to' "$cfg_fn"
		fi
	fi

	if [[ -z $pw_id ]]; then
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

		if [[ ! $line =~ ${regex[volume]} ]]; then
			continue
		fi

		volume[in]=$(tr -d '.' <<<"${BASH_REMATCH[1]}")

		if [[ ${volume[in]} =~ ${regex[zero]} ]]; then
			volume[in]="${BASH_REMATCH[1]}"
		fi

		break
	done

	if [[ -z ${volume[in]} ]]; then
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

	pw-cli s "$pw_id" Props "{ mute: ${mute_tmp}, channelVolumes: [ ${volume[dec]}, ${volume[dec]} ] }" 1>&- 2>&-
}

# Creates a function, called 'reset_volume', which resets the volume.
reset_volume () {
	volume[out]="${volume[no]}"

	set_volume 'false'

	until [[ ${volume[out]} -eq ${volume[full]} ]]; do
		(( volume[out] += 100000 ))

		if [[ ${volume[out]} -gt ${volume[full]} ]]; then
			volume[out]="${volume[full]}"
		fi

		sleep 0.1

		set_volume 'false'
	done
}

# Creates a function, called 'sleep_low', which sleeps and then lowers
# the volume.
sleep_low () {
	declare diff

	diff="$1"

	sleep "$interval"

	if [[ $diff -ge ${volume[out]} ]]; then
		volume[out]=0
	else
		(( volume[out] -= diff ))
	fi

	set_volume 'false'

	printf '%s\n' "${volume[out]}"
}

# Creates a function, called 'get_count', which will get the exact
# number to decrease the volume by every 10 seconds. Since Bash can't do
# floating-point arithmetic, this becomes slightly tricky. Keep in mind
# that Bash always rounds down, never up. I've chosen 354 as the unit
# because then it'll be exactly 1 minute left to take care of potential
# remaining value.
get_count () {
	declare diff rem

# Calculates the difference between current volume and target volume.
	diff=$(( volume[out] - volume[target] ))

# If the difference is greater than (or equal to) 354, do some
# calculations. Otherwise just decrease by 0 until the very last second,
# and then decrease volume by the full difference. There's no need to
# lower the volume gradually, if the difference is very small.
	if [[ $diff -ge $unit ]]; then
		count[0]=$(( diff / unit ))
		rem=$(( diff % unit ))

# If there's a remaining value, then divide that value by 5, which will
# be for 354-359. If there's still a remaining value after that, then
# set ${count[2]} to that value. This will be used for the last instance
# of lowering the volume.
		if [[ $rem -ge 5 ]]; then
			count[1]=$(( rem / 5 ))
			count[2]=$(( rem % 5 ))
		else
			count[2]="$rem"
		fi
	else
		count[2]="$diff"
	fi
}

# Creates a function, called 'spin', which will show a simple animation,
# while waiting for the command output.
spin () {
	declare s
	declare -a spinner

	spinner=('   ' '.  ' '.. ' '...')

	while [[ 1 ]]; do
		for s in "${spinner[@]}"; do
			printf '\r%s%s' 'Wait' "$s"
			sleep 0.5
		done
	done
}

# Gets the PipeWire id.
get_id

# Gets the volume.
get_volume

# We (re)set the original volume as full volume, cause otherwise the
# first lowering of volume is going to be much lower to the ears than
# the value set in PipeWire. The volume set in the desktop environment
# seems to be indpendent of the volume set in PipeWire, which might be
# what's causing this.
reset_volume

# If volume is greater than target volume, then...
if [[ ${volume[out]} -gt ${volume[target]} ]]; then
	get_count

# Starts the spinner animation...
	spin &
	spin_pid="$!"

	printf '%s\n' "${volume[out]}"

# For the first 354 10-second intervals, lower the volume by the value
# in ${count[0]}
	for n in {1..354}; do
		sleep_low "${count[0]}"
	done

# For 354-359, lower the volume by the value in ${count[1]}
	for n in {1..5}; do
		sleep_low "${count[1]}"
	done

# Finally lower the volume by the value in ${count[2]}
	sleep_low "${count[2]}"

	kill "$spin_pid"
	printf '\n'
fi
