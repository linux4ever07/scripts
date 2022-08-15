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

regex_p='([0-9]{2}):([0-9]{2}):([0-9]{2}),([0-9]{3})'
regex_d=' --> '
regex_f="^${regex_p}${regex_d}${regex_p}$"

usage () {
	printf '%s\n' "Usage: $(basename "$0") [srt]"
	exit
}

if=$(readlink -f "$1" 2>&-)
of_tmp="${if%.[^.]*}"
of="${of_tmp}-${RANDOM}.srt"

if [[ ! -f $if ]]; then
	usage
fi

mapfile -t lines < <(tr -d '\r' <"$if")

declare -a duration

# Creates a function called 'time_break', which breaks the 'time line'
# up in parts ($h $m $s $cs).
time_break () {
	time="$1"

	mapfile -d' ' -t time_split < <(sed -E "s/${regex_p}/\1 \2 \3 \4/" <<<"$time")

	h=$(sed -E 's/^0//' <<<"${time_split[0]}")
	m=$(sed -E 's/^0//' <<<"${time_split[1]}")
	s=$(sed -E 's/^0//' <<<"${time_split[2]}")
	cs=$(sed -E 's/^0{1,2}//' <<<"${time_split[3]}")

	printf '%s' "$h $m $s $cs"
}

# Creates a function called 't_time_break', which will be used by the
# 't_time_calc' function to figure out if the time value of the previous
# 'time line' is equal to (or greater than) the current one.
t_time_break () {
	h="$1"
	m="$2"
	s="$3"
	cs="$4"

# Converts all the numbers to centiseconds, because those kind of values
# will be easier to compare in the 't_time_calc' function.
	h=$(( h * 60 * 60 * 1000 ))
	m=$(( m * 60 * 1000 ))
	s=$(( s * 1000 ))

	total_time=$(( h + m + s + cs ))

	printf '%s' "$total_time"
}

# Creates a function called 'cs_calc', which will calculate the total
# number of centiseconds.
cs_calc () {
	cs_in="$1"

# Saves the last 2 (or 1) digits of $cs_in in $cs_tmp
	cs_tmp=$(sed -E -e 's/.*(..)$/\1/' -e 's/^0//' <<<"$cs_in")

# If $cs_tmp is greater than 50, round it up, and if not, round it down.
	if [[ $cs_tmp -ge 50 ]]; then
		cs=$(( (cs_in - cs_tmp) + 100 ))
	else
		cs=$(( cs_in - cs_tmp ))
	fi

	printf '%s' "$cs"
}

# Creates a function called 'c_time_calc', which will calculate the
# total time of the current 'time line'.
c_time_calc () {
	h="$1"
	m="$2"
	s="$3"
	cs="$4"

	cs=$(cs_calc "$cs")

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

	printf '%s' "$h $m $s $cs"
}

# Creates a function called 't_time_calc', which will add the total time
# of the previous 'time line' to the current 'time line', plus a
# centisecond if centiseconds are identical with previous 'time line'.
t_time_calc () {
	total_start_time=("$1" "$2" "$3" "$4")
	total_stop_time=("$5" "$6" "$7" "$8")

# Converts previous and current 'time line' to centiseconds...
	c_tmp=$(t_time_break "${total_start_time[@]}")
	p_tmp=$(t_time_break "${total_stop_time[@]}")

# Until the value of the current 'time_line' is higher than the
# previous, add 1 centisecond.
	until [[ $c_tmp -gt $p_tmp ]]; do
		total_start_time[3]=$(( ${total_start_time[3]} + 100 ))
		c_tmp=$(t_time_break "${total_start_time[@]}")
	done

	mapfile -d' ' -t total_start_time < <(c_time_calc "${total_start_time[@]}")

	printf '%s\n' "${total_start_time[@]}"
}

for (( i = 0; i < ${#lines[@]}; i++ )); do
	line="${lines[${i}]}"

	if [[ ! $line =~ $regex_f ]]; then
		continue
	fi

	mapfile -d' ' -t duration <<<"${line/${regex_d}/ }"
	duration[0]=$(tr -d '[:blank:]' <<<"${duration[0]}")
	duration[1]=$(tr -d '[:blank:]' <<<"${duration[1]}")

	mapfile -d' ' -t c_total_start_time < <(time_break "${duration[0]}")
	mapfile -d' ' -t c_total_start_time < <(c_time_calc "${c_total_start_time[@]}")

	mapfile -d' ' -t c_total_stop_time < <(time_break "${duration[1]}")
	mapfile -d' ' -t c_total_stop_time < <(c_time_calc "${c_total_stop_time[@]}")

	if [[ -n ${p_total_stop_time[@]} ]]; then
		mapfile -t c_total_start_time < <(t_time_calc "${c_total_start_time[@]}" "${p_total_stop_time[@]}")
	fi

	p_total_stop_time=("${c_total_stop_time[@]}")

	start_h="${c_total_start_time[0]}"
	start_m="${c_total_start_time[1]}"
	start_s="${c_total_start_time[2]}"
	start_cs="${c_total_start_time[3]}"

	stop_h="${c_total_stop_time[0]}"
	stop_m="${c_total_stop_time[1]}"
	stop_s="${c_total_stop_time[2]}"
	stop_cs="${c_total_stop_time[3]}"

	finished_line_start=$(printf '%02d:%02d:%02d,%03d' "$start_h" "$start_m" "$start_s" "$start_cs")
	finished_line_stop=$(printf '%02d:%02d:%02d,%03d' "$stop_h" "$stop_m" "$stop_s" "$stop_cs")
	finished_line="${finished_line_start}${regex_d}${finished_line_stop}"
	lines[${i}]="$finished_line"

	printf '%s\n' '***'
	printf '%s\n' "$finished_line"
done

# Writes the array to $of (output file).
for (( i = 0; i < ${#lines[@]}; i++ )); do
	printf '%s\r\n' "${lines[${i}]}"
done > "$of"
