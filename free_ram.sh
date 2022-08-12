#!/bin/bash
# This script creates an infinite while loop, which checks the available
# RAM every 1 second, and kills Firefox, Chrome, Chromium and
# Tor Browser if less than 1 GB is available. The script will only kill
# the tabs, but not the main window itself, so the application keeps
# running but RAM is still freed up.
#
# The web browser is always the application that ends up using the most
# RAM on my system. Once the RAM is nearly full, Linux starts swapping
# and gradually slows down more and more, until grinding to a complete
# halt when RAM is completely full. Then Linux calls the Out Of Memory
# (OOM) manager to kill processes to free up RAM. It might kill a
# critical process, a program that's been running for a very long time
# (i.e. video encoding). To prevent that from happening, I created
# this script.

# Creates a function called 'now', which will print the date and time.
now () { date '+%F %H:%M:%S'; }

limit=1000000

regex='^[[:space:]]*$'
regex_rend='--type=renderer'
regex_ext='--extension-process'

# Creates a function called 'is_chromium', which checks if Chromium
# or Chrome is running.
is_chromium () {
	for comm in chrome chromium; do
		pgrep "$comm" | tr -d '[:blank:]'
	done
}

# Creates a function called 'kill_chromium', which kills all child
# processes belonging to either Chromium or Chrome.
kill_chromium () {
	pid_switch=0

	for comm in chrome chromium; do

		mapfile -t parent < <(ps -C "$comm" -o ppid | tail -n +2 | tr -d '[:blank:]' | sort -u)
		mapfile -t child < <(ps -C "$comm" -o pid | tail -n +2 | tr -d '[:blank:]')

		for (( i = 0; i < ${#child[@]}; i++ )); do
			if [[ ! ${child[${i}]} =~ $regex ]]; then
				child_pid="${child[${i}]}"

				for (( j = 0; j < ${#parent[@]}; j++ )); do
					if [[ ! ${parent[${j}]} =~ $regex ]]; then
						parent_pid="${parent[${j}]}"

						if [[ $parent_pid == $child_pid ]]; then
							pid_switch=1
						fi
					fi
				done

# Adding an extra check, which checks if $child_pid is a renderer /
# extension process. If it's NOT a renderer, set $pid_switch to '1',
# preventing it from being killed. If the process is an extension
# process, also set $pid_switch to '1'. This will keep extensions and
# downloads running, even though the other Chrome child processes are
# killed. Only renderer processes that are NOT extension processes will
# get killed.
				chrome_type=$(ps -p "$child_pid" -o args | tail -n +2)

				if [[ ! $chrome_type =~ $regex_rend ]]; then
					pid_switch=1
				elif [[ $chrome_type =~ $regex_ext ]]; then
# if [[ $chrome_type =~ $regex_ext ]]; then
					pid_switch=1
				fi

				if [[ $pid_switch -eq 0 ]]; then
					printf '%s\n' "SIGKILL: ${child_pid}"
					kill -9 "$child_pid"
				else
					pid_switch=0
				fi
			fi
		done
	done
}

# Creates a function called 'kill_firefox', which kills all child
# processes belonging to either Firefox or Tor Browser.
kill_firefox () {
	declare -a pids_tmp pids

	for name in 'Web Content' 'WebExtensions'; do
		mapfile -t pids_tmp < <(pgrep -x "$name" | tr -d '[:blank:]')
		pids+=("${pids_tmp[@]}")
	done

	for name in firefox tor; do
		for (( i = 0; i <= ${#pids[@]}; i++ )); do
			if [[ ! ${pids[${i}]} =~ $regex ]]; then
				pid="${pids[${i}]}"
				p_name=$(ps -p "$pid" -o comm | tail -n +2)
				if [[ $p_name == $name ]]; then
					unset -v pids[${i}]
				fi
			fi
		done
	done

	kill -9 "${pids[@]}"
}

# Creates a file name for the log.
log_killed="${HOME}/firefox_chromium_killed.log"

# If $log_killed is not a file, create it.
if [[ ! -f $log_killed ]]; then
	touch "$log_killed"
fi

# Creates an infinite while loop.
while true; do
# Sleeps for 1 second.
	sleep 1

# Unsets $free_ram, since this might not be the first time the loop is
# run.
	unset -v free_ram

# Runs 'free', stores output in the $free_ram array, and sets a couple
# of variables based on that output.
	mapfile -t free_ram < <(free | sed -E 's/[[:space:]]+/ /g')
	ram=$(cut -d' ' -f4 <<<"${free_ram[1]}")
	swap=$(cut -d' ' -f4 <<<"${free_ram[2]}")
	avail=$(cut -d' ' -f7 <<<"${free_ram[1]}")

# Prints the free and available RAM and SWAP.
	printf '%s\n' "FREE (kibibytes)"
	printf '%s\n' "RAM: ${ram}, SWAP: ${swap}"
	printf '%s\n' "***"
	printf '%s\n' "AVAILABLE (kibibytes)"
	printf '%s\n\n' "RAM: ${avail}"

# If available RAM is less than 1GB...
	if [[ $avail -lt $limit ]]; then
# Checks if Firefox and Chromium are running. $is_chromium is an array,
# since the output probably spans across multiple lines, due to Chromium
# being highly multithreaded and keeping separate threads / processes
# for every window and tab.
		is_firefox=$(pgrep -x firefox)
		is_tor=$(pgrep -x tor)
		mapfile -t is_chromium < <(is_chromium)

# If Firefox is running, then kill it, print a message to the screen,
# and append a message to the log.
		if [[ $is_firefox ]]; then
			time=$(now)

			printf '%s\n\n' "${time}: Killing Firefox..." | tee --append "$log_killed"
			kill_firefox
		fi

# If Tor Browser is running, then kill it, print a message to the
# screen, and append a message to the log.
		if [[ $is_tor ]]; then
			time=$(now)

			printf '%s\n\n' "${time}: Killing Tor Browser..." | tee --append "$log_killed"
			kill_firefox
		fi

# If Chromium is running, then...
		if [[ ! ${is_chromium[0]} =~ $regex ]]; then
			time=$(now)

			printf '%s\n\n' "${time}: Killing Chromium..." | tee --append "$log_killed"
			kill_chromium
		fi

# Writes cached writes to disk. Hopefully this will also clear up a
# little RAM.
		sync
	fi
done
