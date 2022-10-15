#!/bin/bash

# This script reads from the prompt, and uses numbers in the format:
# 00:00:00 (mm:ss:ff). Minutes, seconds and frames. There are 75 frames
# in one second, according to the Cue sheet specification. Each time a
# number is given, it's added to the total number. The script is based
# around an infinite while loop, and only quits once killed or Ctrl+C is
# pressed.

regex_frames='^[0-9]+$'
regex_time='[0-9]{2}:[0-9]{2}:[0-9]{2}'

# Creates a function called 'time_convert', which converts track length
# back and forth between the time (mm:ss:ff) format and frames /
# sectors.
time_convert () {
	time="$1"

	m=0
	s=0
	f=0

# If argument is in the mm:ss:ff format...
	if [[ $time =~ $regex_time ]]; then
		mapfile -t time_split < <(tr ':' '\n'  <<<"$time" | sed -E 's/^0//')

# Converting minutes and seconds to frames, and adding all the numbers
# together.
		m=$(( ${time_split[0]} * 60 * 75 ))
		s=$(( ${time_split[1]} * 75 ))
		f="${time_split[2]}"

		time=$(( m + s + f ))

# If argument is in the frame format...
	elif [[ $time =~ $regex_frames ]]; then
		f="$time"

# While $f (frames) is equal to (or greater than) 75, clear the $f
# variable and add 1 to the $s (seconds) variable.
		while [[ $f -ge 75 ]]; do
			s=$(( s + 1 ))
			f=$(( f - 75 ))
		done

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
t=1
frames=0

printf '\n%s\n\n' "This script will calculate the total time of all the times given."
printf '%s\n\n' "Type or paste a time in the mm:ss:ff format."

while true; do
# Read input.
	read in

	if [[ ! $in =~ $regex_time ]]; then
		continue
	fi

# Add 1 to the track ($t) variable.
	let t++

# Convert time to frames, and add that number to the total number in the
# $frames variable. Convert that number back to the mm:ss:ff format.
	tmp_frames=$(time_convert "$in")
	frames=$(( frames + tmp_frames ))
	time=$(time_convert "$frames")

# Prints the current total time in the mm:ss:ff format.
	printf "\n*** Track %d start: %s ***\n" "$t" "$time"
done
