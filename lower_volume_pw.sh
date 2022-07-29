#!/bin/bash
# This script slowly and gradually lowers the volume until it's equal to
# 0%. Although, any target volume can be set using the $target_volume
# variable. The script takes 1 hour (360 * 10 seconds) all in all, to
# completely lower the volume to the target volume.
# I'm using this script to automatically lower the volume when I fall
# asleep to watching a movie or YouTube.

# https://gitlab.freedesktop.org/pipewire/pipewire/-/wikis/Migrate-PulseAudio

regex_sink='^id ([0-9]+),'
regex_target='^media\.class = \"Audio/Sink\"'
regex_volume='^\"channelVolumes\": \[ ([0-9]+\.[0-9]+), [0-9]+\.[0-9]+ \],'
full_volume='1000000'
no_volume='0'
target_volume='0'
interval='10'

# trap ctrl-c and call ctrl_c()
trap ctrl_c INT

# If a SIGINT signal is captured, then put the volume back to where it
# was before running this script.
ctrl_c () {
	if [[ $pw_id ]]; then
		set_volume "$volume_og" 'false'
	fi

	printf '%s\n' '** Trapped CTRL-C'

	exit
}

# Creates a function called 'get_volume', which gets the current volume.
get_volume () {
	mapfile -t pw_info < <(pw-cli ls Node | sed -E -e 's/^[[:blank:]]*//' -e 's/[[:space:]]+/ /g')

	switch='0'

	for (( i = 0; i < ${#pw_info[@]}; i++ )); do
		line_i="${pw_info[${i}]}"

		if [[ $line_i =~ $regex_sink ]]; then
			pw_id="${BASH_REMATCH[1]}"

			n=$(( i + 1 ))

			for (( j = n; j < ${#pw_info[@]}; j++ )); do
				line_j="${pw_info[${j}]}"

				if [[ $line_j =~ $regex_sink ]]; then
					break
				elif [[ $line_j =~ $regex_target ]]; then
					switch='1'
					break
				fi
			done
		fi

		if [[ $switch -eq 1 ]]; then
			break
		fi
	done

	if [[ -z $pw_id ]]; then
		exit
	fi

	mapfile -t pw_dump < <(pw-dump "$pw_id" | sed -E -e 's/^[[:blank:]]*//' -e 's/[[:space:]]+/ /g')

	for (( i = 0; i < ${#pw_dump[@]}; i++ )); do
		line="${pw_dump[${i}]}"

		if [[ $line =~ $regex_volume ]]; then
			volume=$(tr -d '.' <<<"${BASH_REMATCH[1]}" | sed -E 's/^0+//')

			if [[ ${#volume} -eq 0 ]]; then
				volume='0'
			fi

			break
		fi
	done

	if [[ -z $volume ]]; then
		exit
	fi

	printf '%s' "${volume} ${pw_id}"
}

# Creates a function called 'set_volume', which sets the volume.
set_volume () {
	volume_tmp="$1"
	mute_tmp="$2"

	if [[ ${#volume_tmp} -gt 6 ]]; then
		volume_1="${volume_tmp%??????}"
		volume_2="${volume_tmp#${volume_1}}"
		volume_2=$(sed -E 's/^0+//' <<<"$volume_2")

		if [[ ${#volume_2} -eq 0 ]]; then
			volume_2='0'
		fi
	else
		volume_1='0'
		volume_2="$volume_tmp"
	fi

	volume_dec=$(printf '%d.%06d' "$volume_1" "$volume_2")

	pw-cli s "$pw_id" Props "{ mute: ${mute_tmp}, channelVolumes: [ ${volume_dec}, ${volume_dec} ] }" 1>&- 2>&-
}

# Creates a function called 'reset_volume', which resets the volume.
reset_volume () {
	volume_tmp="$no_volume"

	set_volume "$volume_tmp" 'false'

	until [[ $volume_tmp -eq $full_volume ]]; do
		volume_tmp=$(( volume_tmp + 100000 ))

		if [[ $volume_tmp -gt $full_volume ]]; then
			volume_tmp="$full_volume"
		fi

		sleep 0.1

		set_volume "$volume_tmp" 'false'
	done

	printf '%s' "$volume_tmp"
}

# Creates a function called 'sleep_low', which sleeps and then lowers
# the volume.
sleep_low () {
	n="$1"

	sleep "$interval"

	if [[ $n -ge $volume ]]; then
		volume='0'
	else
		volume=$(( volume - n ))
	fi

	set_volume "$volume" 'false'

	printf '%s' "$volume"
}

# Creates a function called 'get_count', which will get the exact number
# to decrease the volume by every 10 seconds. Since Bash can't do
# floating-point arithmetic, this becomes slightly tricky. Keep in mind
# that Bash always rounds down, never up. I've chosen 354 as the unit
# because then it'll be exactly 1 minute left to take care of potential
# remaining value.
get_count () {
	diff="$1"
	unit='354'
	count[0]=$(( diff / unit ))
	test=$(( unit * ${count[0]} ))

# If there's a remaining value, then divide that value by 5, which will
# be for 354-359.
	if [[ $test -lt $diff ]]; then
		tmp=$(( diff - test ))
		count[1]=$(( tmp / 5 ))

		for n in {1..5}; do
			tmp=$(( tmp - ${count[1]} ))
		done

# If there's still a remaining value, then set ${count[2]} to that
# value. This will be used for the last instance of running the 'pw-cli'
# command (and lowering the volume).
		count[2]="$tmp"
	else
		count[1]='0'
		count[2]='0'
	fi

	printf '%s\n' "${count[@]}"
}

# Creates a function called 'spin', which will show a simple animation,
# while waiting for the command output.
spin () {
	spinner=( '   ' '.  ' '.. ' '...' )

	while true; do
		for s in "${spinner[@]}"; do
			printf '\r%s' "Wait${s}"
			sleep 0.5
		done
	done
}

# Gets the volume and id.
mapfile -d' ' -t volume_out < <(get_volume)

volume_og="${volume_out[0]}"
pw_id="${volume_out[1]}"
volume="$volume_og"

# We (re)set the original volume as full volume, cause otherwise the
# first lowering of volume is going to be much lower to the ears than
# the value set in PipeWire. The volume set in the desktop environment
# seems to be indpendent of the volume set in PipeWire, which might be
# what's causing this.
volume=$(reset_volume)

# If volume is greater than target volume, then...
if [[ $volume -gt $target_volume ]]; then
# Calculates the difference between current volume and target volume.
	diff=$(( volume - target_volume ))

# If the difference is greater than 360 (the unit used in this script),
# then run the get_count function, otherwise just decrease by 0 until
# the very last second, and then decrease volume by the full difference.
# There's no need to lower the volume gradually, if the difference is
# very small.
	if [[ $diff -gt 360 ]]; then
		mapfile -t count < <(get_count "${diff}")
	else
		count=('0' '0' "${diff}")
	fi

# Starts the spinner animation...
	spin &
	spin_pid="$!"

	printf '%s\n' "$volume"

# For the first 354 10-second intervals, lower the volume by the value
# in ${count[0]}
	for n in {1..354}; do
		volume=$(sleep_low "${count[0]}")
		printf '%s\n' "$volume"
	done

# For 354-359, lower the volume by the value in ${count[1]}
	for n in {1..5}; do
		volume=$(sleep_low "${count[1]}")
		printf '%s\n' "$volume"
	done

# Finally lower the volume by the value in ${count[2]}
	volume=$(sleep_low "${count[2]}")
	printf '%s\n' "$volume"

	kill "$spin_pid"
	printf '\n'
fi
