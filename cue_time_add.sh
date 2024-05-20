#!/bin/bash

# This script reads from the prompt, and uses numbers in the format:
# 00:00:00 (mm:ss:ff). Minutes, seconds and frames. There are 75 frames
# in one second, according to the Cue sheet specification. Each time a
# number is given, it's added to the total number. The script is based
# around an infinite while loop, and only quits once killed or Ctrl+C is
# pressed.

declare track_n frames in out
declare -a format

format[0]='^[0-9]+$'
format[1]='^([0-9]{2,}):([0-9]{2}):([0-9]{2})$'

# Creates a function, called 'time_convert', which converts track
# timestamps back and forth between the time (mm:ss:ff) format and
# frames / sectors.
time_convert () {
	declare time m s f

	time="$1"

# If argument is in the mm:ss:ff format...
	if [[ $time =~ ${format[1]} ]]; then
		m="${BASH_REMATCH[1]#0}"
		s="${BASH_REMATCH[2]#0}"
		f="${BASH_REMATCH[3]#0}"

# Converts minutes and seconds to frames, and adds all the numbers
# together.
		m=$(( m * 60 * 75 ))
		s=$(( s * 75 ))

		time=$(( m + s + f ))

# If argument is in the frame format...
	elif [[ $time =~ ${format[0]} ]]; then
		f="$time"

# Converts frames to seconds and minutes.
		s=$(( f / 75 ))
		m=$(( s / 60 ))

		f=$(( f % 75 ))
		s=$(( s % 60 ))

		time=$(printf '%02d:%02d:%02d' "$m" "$s" "$f")
	fi

	printf '%s' "$time"
}

# Initiates the global variables. For counting the iterations of the
# loop (track number), and storing the total time in frames.
track_n=1
frames=0

printf '\n%s\n\n' "This script will calculate the total time of all the times given."
printf '%s\n\n' "Type or paste a time in the mm:ss:ff format."

while [[ 1 ]]; do
# Reads input.
	read in

# Continues the next iteration of the loop if input doesn't match the
# correct format.
	if [[ ! $in =~ ${format[1]} ]]; then
		continue
	fi

# Adds 1 to the track number.
	(( track_n += 1 ))

# Converts time to frames, and adds that number to the total time.
# Converts that number back to the mm:ss:ff format.
	in=$(time_convert "$in")
	(( frames += in ))
	out=$(time_convert "$frames")

# Prints the current total time in the mm:ss:ff format.
	printf "\n*** Track %d start: %s ***\n" "$track_n" "$out"
done
