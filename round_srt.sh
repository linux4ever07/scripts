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

usage () {
	printf '\n%s\n\n' "Usage: $(basename "$0") [srt]"
	exit
}

if=$(readlink -f "$1")
if_bn=$(basename "$if")
if_bn_lc="${if_bn,,}"

session="${RANDOM}-${RANDOM}"
of="${if%.*}-${session}.srt"

if [[ ! -f $if || ${if_bn_lc##*.} != 'srt' ]]; then
	usage
fi

declare -a format

delim=' --> '

format[0]='^[0-9]+$'
format[1]='^([0-9]{2}):([0-9]{2}):([0-9]{2}),([0-9]{3})$'
format[2]='[0-9]{2}:[0-9]{2}:[0-9]{2},[0-9]{3}'
format[3]="^(${format[2]})${delim}(${format[2]})$"

regex_blank='^[[:blank:]]*(.*)[[:blank:]]*$'
regex_zero='^0+([0-9]+)$'

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

	cs_last=0

	regex_last2='^[0-9]*([0-9]{2})$'

# If argument is in the hh:mm:ss format...
	if [[ $time =~ ${format[1]} ]]; then
		h="${BASH_REMATCH[1]#0}"
		m="${BASH_REMATCH[2]#0}"
		s="${BASH_REMATCH[3]#0}"
		cs="${BASH_REMATCH[4]}"

		if [[ $cs =~ $regex_zero ]]; then
			cs="${BASH_REMATCH[1]}"
		fi

# Converts all the numbers to centiseconds, because those kind of values
# will be easier to compare in the 'time_calc' function.
		h=$(( h * 60 * 60 * 1000 ))
		m=$(( m * 60 * 1000 ))
		s=$(( s * 1000 ))

# Saves the last 2 (or 1) digits of $cs in $cs_last.
		if [[ $cs =~ $regex_last2 ]]; then
			cs_last="${BASH_REMATCH[1]#0}"
		fi

# If $cs_last is greater than 50, round it up, and if not, round it down.
		if [[ $cs_last -ge 50 ]]; then
			cs=$(( (cs - cs_last) + 100 ))
		else
			cs=$(( cs - cs_last ))
		fi

		time=$(( h + m + s + cs ))

# If argument is in the centisecond format...
	elif [[ $time =~ ${format[0]} ]]; then
		cs="$time"

		s=$(( cs / 1000 ))
		m=$(( s / 60 ))
		h=$(( m / 60 ))

		cs=$(( cs % 1000 ))
		s=$(( s % 60 ))
		m=$(( m % 60 ))

		time=$(printf '%02d:%02d:%02d,%03d' "$h" "$m" "$s" "$cs")
	fi

	printf '%s' "$time"
}

# Creates a function called 'time_calc', which makes sure the current
# 'time line' is at least 1 centisecond greater than previous
# 'time line'.
time_calc () {
	start_time_tmp="$1"
	stop_time_tmp="$2"

# If the previous 'time line' is greater than the current one, make the
# current 'time line' 1 centisecond greater than that.
	if [[ $stop_time_tmp -gt $start_time_tmp ]]; then
		start_time_tmp=$(( stop_time_tmp + 100 ))
	fi

	printf '%s' "$start_time_tmp"
}

for (( i = 0; i < ${#lines[@]}; i++ )); do
	line=$(sed -E "s/${regex_blank}/\1/" <<<"${lines[${i}]}")

	if [[ ! $line =~ ${format[3]} ]]; then
		continue
	fi

	start_time=$(time_convert "${BASH_REMATCH[1]}")
	stop_time=$(time_convert "${BASH_REMATCH[2]}")

	if [[ -n $previous ]]; then
		start_time=$(time_calc "$start_time" "$previous")
	fi

	previous="$stop_time"

	start_time=$(time_convert "$start_time")
	stop_time=$(time_convert "$stop_time")

	time_line="${start_time}${delim}${stop_time}"
	lines["${i}"]="$time_line"
done

# Writes the array to $of (output file).
printf '%s\r\n' "${lines[@]}" > "$of"

printf '\n%s %s\n\n' 'Wrote file:' "$of"
