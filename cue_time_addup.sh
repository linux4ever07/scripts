#!/bin/bash
# This script reads from the prompt, and uses numbers in the format:
# 00:00:00 (mm:ss:ff). Minutes, seconds and frames. There are 75 frames
# in one second, according to the Cue sheet specification. Each time a
# number is given, it's added to the total number. The script is based
# around an infinite while loop, and only quits once killed or Ctrl+C is
# pressed.

# Initiate the global variables, minutes ($mm), seconds ($ss) and frames
# ($frames). And also $t, for counting the iterations of the loop, which
# will be echoed as track number.
mm=0
ss=0
ff=0
t=1

printf '\n%s\n\n' "This script will calculate the total time of all the times given."
printf '%s\n\n' "Type or paste a time in the mm:ss:ff format."

while true; do
# Read input.
	read in

# Break up the input string.
	mapfile -d':' -t in_array <<<"$in"

# Add 1 to the track ($t) variable.
	let t++

# Cut the input string, and get field 1, then set the minutes ($mm)
# variable.
	tmp=$(sed 's/^0//' <<<"${in_array[0]}")
	mm=$(( mm + tmp ))

# Cut the input string, and get field 2, then set the seconds ($ss)
# variable.
	tmp=$(sed 's/^0//' <<<"${in_array[1]}")
	ss=$(( ss + tmp ))

# If seconds are greater than 60, then calculate the remainder ($rem),
# else set the remainder ($rem) variable to 0.
	if [[ $ss -gt 60 ]]; then
		rem=$(( ss % 60 ))
	else
		rem=0
	fi

# If seconds are equal to 60, then add 1 to the minutes ($mm) variable,
# and reset the seconds ($ss) variable to 0. If remainder ($rem) is
# greater than 0, then add 1 to the minutes ($mm) variable, and set the
# seconds ($ss) variable to $rem.
	if [[ $ss -eq 60 ]]; then
		let mm++
		ss=0
	elif [[ $rem -gt 0 ]]; then
		let mm++
		ss="$rem"
	fi

# Cut the input string, and get field 3, then set the frames ($ff)
# variable.
	tmp=$(sed 's/^0//' <<<"${in_array[2]}")
	ff=$(( ff + tmp ))

# If frames are greater than 75, then calculate the remainder ($rem),
# else set the remainder ($rem) variable to 0.
	if [[ $ff -gt 75 ]]; then
		rem=$(( ff % 75 ))
	else
		rem=0
	fi

# If frames are equal to 75, then add 1 to the seconds ($ss) variable,
# and reset the frames ($ff) variable to 0. If remainder ($rem) is
# greater than 0, then add 1 to the seconds ($ss) variable, and set the
# frames ($ff) variable to $rem.
	if [[ $ff -eq 75 ]]; then
		let ss++
		ff=0
	elif [[ $rem -gt 0 ]]; then
		let ss++
		ff="$rem"
	fi

# Unsets the temporary ($tmp) and remainder ($rem) variables for the
# next iteration of the while loop.
	unset -v tmp rem

# If the minutes ($mm) variable is greater than (or equal to) 100, reset
# it to the remainder.
	if [[ $mm -ge 100 ]]; then
		mm=$(( mm % 100 ))
	fi

# Prints the current total time in the mm:ss:ff format.
	printf "\n*** Track %d start: %02d:%02d:%02d ***\n" $t $mm $ss $ff
done

