#!/bin/bash

# This script will round all the centiseconds in an SRT subtitle file.
# Every start time and end time of a subtitle will now end in ,?00

# Example: 00:20:47,500 --> 00:20:52,600
# Instead of: 00:20:47,457 --> 00:20:52,611

# This makes it a lot easier to edit the subtitle in for example Gnome
# Subtitles, if needed. Even if you're not going to edit the subtitle
# afterwards, it just looks better using whole centiseconds. The output
# filename is the same as the input filename, only a random number is
# added to the name. The start and end times of every subtitle line are
# adjusted so they don't overlap. They will all differ by at least 1
# centisecond.

regex_time='([0-9]{2}):([0-9]{2}):([0-9]{2}),([0-9]{3})'
regex_cs='^[0-9]+$'
delim=' --> '
regex_full="^${regex_time}${delim}${regex_time}$"
regex_blank='^[[:blank:]]*(.*)[[:blank:]]*$'

usage () {
	printf '%s\n' "Usage: $(basename "$0") [srt]"
	exit
}

if=$(readlink -f "$1" 2>&-)
session="${RANDOM}-${RANDOM}"
of="${if%.[^.]*}"
of="${of}-${session}.srt"

if [[ ! -f $if ]]; then
	usage
fi

mapfile -t lines < <(tr -d '\r' <"$if")

# Creates a function called 'time_convert', which converts the
# 'time line' back and forth between the time (hh:mm:ss) format and
# centiseconds.
time_convert () {
	time="$1"

	h=0
	m=0
	s=0
	cs=0

# If argument is in the hh:mm:ss format...
	if [[ $time =~ $regex_time ]]; then
		mapfile -d' ' -t time_split < <(sed -E "s/${regex_time}/\1 \2 \3 \4/" <<<"$time")

		h=$(sed -E 's/^0//' <<<"${time_split[0]}")
		m=$(sed -E 's/^0//' <<<"${time_split[1]}")
		s=$(sed -E 's/^0//' <<<"${time_split[2]}")
		cs=$(sed -E 's/^0{1,2}//' <<<"${time_split[3]}")

# Converts all the numbers to centiseconds, because those kind of values
# will be easier to compare in the 'time_calc' function.
		h=$(( h * 60 * 60 * 1000 ))
		m=$(( m * 60 * 1000 ))
		s=$(( s * 1000 ))

# Saves the last 2 (or 1) digits of $cs in $cs_tmp.
		cs_tmp=$(sed -E -e 's/^.*(..)$/\1/' -e 's/^0//' <<<"$cs")

		if [[ -z $cs_tmp ]]; then
			cs_tmp=0
		fi

# If $cs_tmp is greater than 50, round it up, and if not, round it down.
		if [[ $cs_tmp -ge 50 ]]; then
			cs=$(( (cs - cs_tmp) + 100 ))
		else
			cs=$(( cs - cs_tmp ))
		fi

		time=$(( h + m + s + cs ))

# If argument is in the centisecond format...
	elif [[ $time =~ $regex_cs ]]; then
		cs="$time"

# While $cs (centiseconds) is equal to (or greater than) 1000, clear the
# $cs variable and add 1 to the $s (seconds) variable.
		while [[ $cs -ge 1000 ]]; do
			s=$(( s + 1 ))
			cs=$(( cs - 1000 ))
		done

# While $s (seconds) is equal to (or greater than) 60, clear the $s
# variable and add 1 to the $m (minutes) variable.
		while [[ $s -ge 60 ]]; do
			m=$(( m + 1 ))
			s=$(( s - 60 ))
		done

# While $m (minutes) is equal to (or greater than) 60, clear the $m
# variable and add 1 to the $h (hours) variable.
		while [[ $m -ge 60 ]]; do
			h=$(( h + 1 ))
			m=$(( m - 60 ))
		done

# While $h (hours) is equal to 100 (or greater than), clear the $h
# variable.
		while [[ $h -ge 100 ]]; do
			h=$(( h - 100 ))
		done

		time=$(printf '%02d:%02d:%02d,%03d' "$h" "$m" "$s" "$cs")
	fi

	printf '%s' "$time"
}

# Creates a function called 'time_calc', which will add the total time
# of the previous 'time line' to the current 'time line', plus a
# centisecond if centiseconds are identical with previous 'time line'.
time_calc () {
	start_time_tmp="$1"
	stop_time_tmp="$2"

# Until the value of the current 'time_line' is higher than the
# previous, add 1 centisecond.
	until [[ $start_time_tmp -gt $stop_time_tmp ]]; do
		start_time_tmp=$(( start_time_tmp + 100 ))
	done

	printf '%s' "$start_time_tmp"
}

for (( i = 0; i < ${#lines[@]}; i++ )); do
	line=$(sed -E "s/${regex_blank}/\1/" <<<"${lines[${i}]}")

	if [[ ! $line =~ $regex_full ]]; then
		continue
	fi

	mapfile -d' ' -t duration <<<"${line/${delim}/ }"

	start_time=$(time_convert "${duration[0]}")
	stop_time=$(time_convert "${duration[1]}")

	if [[ -n $previous ]]; then
		start_time=$(time_calc "$start_time" "$previous")
	fi

	previous="$stop_time"

	start_time=$(time_convert "$start_time")
	stop_time=$(time_convert "$stop_time")

	finished_line="${start_time}${delim}${stop_time}"
	lines[${i}]="$finished_line"

	printf '%s\n' '***'
	printf '%s\n' "$finished_line"
done

# Writes the array to $of (output file).
for (( i = 0; i < ${#lines[@]}; i++ )); do
	printf '%s\r\n' "${lines[${i}]}"
done > "$of"
