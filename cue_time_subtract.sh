#!/bin/bash

# This script reads from the prompt, and uses numbers in the format:
# 00:00:00 (mm:ss:ff). Minutes, seconds and frames. There are 75 frames
# in one second, according to the Cue sheet specification. Each time a
# number is given, it's subtracted from the total number. The script is
# based around a while loop, and only quits once killed, Ctrl+C is
# pressed or if the $t variable reaches 2.

usage () {
	printf '\n%s\n\n' "Usage: $(basename "$0") [cue endtime] [totaltracks]"
	exit
}

regex_frames='^[0-9]+$'
regex_time='[0-9]{2}:[0-9]{2}:[0-9]{2}'

if [[ -z $1 || -z $2 ]]; then
	usage
elif [[ ! $1 =~ $regex_time || ! $2 =~ $regex_frames ]]; then
	usage
fi

# Creates a function called 'time_convert', which converts track length
# back and forth between the time (mm:ss:ff) format and frames /
# sectors.
time_convert () {
	time="$1"

# If argument is in the mm:ss:ff format...
	if [[ $time =~ $regex_time ]]; then
		mapfile -t time_split < <(tr ':' '\n'  <<<"$time" | sed -E 's/^0//')

# Converting minutes and seconds to frames, and adding all the numbers
# together.
		time_split[0]=$(( ${time_split[0]} * 60 * 75 ))
		time_split[1]=$(( ${time_split[1]} * 75 ))

		time=$(( ${time_split[0]} + ${time_split[1]} + ${time_split[2]} ))

# If argument is in the frame format...
	elif [[ $time =~ $regex_frames ]]; then
		f=$(( time % 75 ))
		s=$(( time / 75 ))

# While $s (seconds) is equal to (or greater than) 60, clear the $s
# variable and add 1 to the $m (minutes) variable.
		while [[ $s -ge 60 ]]; do
			m=$(( m + 1 ))
			s=$(( s - 60 ))
		done

		time=$(printf '%02d:%02d:%02d' "$m" "$s" "$f")
	fi

	printf '%s' "$time"
}

# Initiate the global variable $t, for counting the iterations of the
# loop, which will be echoed as track number. $frames stores the total
# time in frames.
t="$2"
frames=$(time_convert "$1")

printf '\n%s\n\n' "This script will calculate the track length of all the tracks, based on start times given."
printf '%s\n\n' "Type or paste a time in the mm:ss:ff format."

until [[ $t -eq 2 ]]; do
# Read input.
	read in

	if [[ ! $in =~ $regex_time ]]; then
		continue
	fi

# Remove 1 from the track ($t) variable.
	let t--

# Convert time to frames, and subtract that number from the total number
# in the $frames variable. Save the result in the $diff variable, and
# subtract that value from the $frames variable. Convert the value in
# the $diff variable back to the mm:ss:ff format.
	tmp_frames=$(time_convert "$in")
	diff=$(( frames - tmp_frames ))
	frames=$(( frames - diff ))
	time=$(time_convert "$diff")

# Prints the current track length in the mm:ss:ff format.
	printf "\n*** Track %d length: %s ***\n" "$t" "$time"
done