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

ram_limit=1000000

regex_pid_args='^[[:blank:]]*([0-9]+)[[:blank:]]*([^ ]+).*$'
regex_rend='--type=renderer'
regex_ext='--extension-process'
regex_tab='^.*\-childID [0-9]+.* tab$'

# Creates a file name for the log.
log_killed="${HOME}/browser_killed.log"

# If $log_killed is not a file, create it.
if [[ ! -f $log_killed ]]; then
	touch "$log_killed"
fi

# Creates a function called 'get_pids', which gets all child process IDs
# of the command names given to it as arguments.
get_pids () {
	declare -A pids

	for comm in "$@"; do
		regex_comm="^.*${comm}$"

		mapfile -t session < <(ps -C "$comm" -o sid= | tr -d '[:blank:]' | sort -u)

		if [[ ${#session[@]} -eq 0 ]]; then
			continue
		fi

		mapfile -t child < <(ps -g "${session[0]}" -o pid=,args=)

		for (( i = 0; i < ${#child[@]}; i++ )); do
			line="${child[${i}]}"

			if [[ $line =~ $regex_pid_args ]]; then
				pid="${BASH_REMATCH[1]}"
				args="${BASH_REMATCH[2]}"

				if [[ $pid -eq ${session[0]} ]]; then
					continue
				fi

				if [[ $args =~ $regex_comm ]]; then
					pids["${pid}"]="$args"
				fi
			fi
		done
	done

	printf '%s\n' "${!pids[@]}" | sort -n
}

# Creates a function called 'kill_chromium', which kills all child
# processes belonging to either Chromium or Chrome.
kill_chromium () {
	declare -a pids_tmp

	mapfile -t pids_tmp < <(get_pids 'chrome' 'chromium')

	if [[ ${#pids_tmp[@]} -eq 0 ]]; then
		return
	fi

	time=$(now)
	printf '%s\n\n' "${time}: Killing Chrome / Chromium..." | tee --append "$log_killed"

	for (( i = 0; i < ${#pids_tmp[@]}; i++ )); do
		pid="${pids_tmp[${i}]}"
		args=$(ps -p "$pid" -o args=)

# Adding an extra check, which checks if $child_pid is a renderer /
# extension process. If it's NOT a renderer, or is an extension
# process, skip it. This will keep extensions and downloads running,
# even though the other Chrome child processes are killed. Only renderer
# processes that are NOT extension processes will get killed.
		if [[ ! $args =~ $regex_rend ]]; then
			continue
		elif [[ $args =~ $regex_ext ]]; then
			continue
		fi

		printf '%s\n' "SIGKILL: ${pid}"
		kill -9 "$pid"
	done
}

# Creates a function called 'kill_firefox', which kills all child
# processes belonging to either Firefox or Tor Browser.
kill_firefox () {
	declare -a pids_tmp

	mapfile -t pids_tmp < <(get_pids 'firefox' 'firefox.real')

	if [[ ${#pids_tmp[@]} -eq 0 ]]; then
		return
	fi

	time=$(now)
	printf '%s\n\n' "${time}: Killing Firefox / Tor Browser..." | tee --append "$log_killed"

	for (( i = 0; i < ${#pids_tmp[@]}; i++ )); do
		pid="${pids_tmp[${i}]}"
		args=$(ps -p "$pid" -o args=)

		if [[ ! $args =~ $regex_tab ]]; then
			continue
		fi

		printf '%s\n' "SIGKILL: ${pid}"
		kill -9 "$pid"
	done
}

# Creates an infinite while loop.
while true; do
# Sleeps for 1 second.
	sleep 1

# Runs 'free', stores output in the $free_ram array, and sets a couple
# of variables based on that output.
	mapfile -t free_ram < <(free | sed -E 's/[[:blank:]]+/ /g')
	mapfile -d' ' -t ram <<<"${free_ram[1]}"
	mapfile -d' ' -t swap <<<"${free_ram[2]}"
	ram[-1]="${ram[-1]%$'\n'}"
	swap[-1]="${swap[-1]%$'\n'}"

# Prints the free and available RAM and SWAP.
	printf '%s\n' 'FREE (kibibytes)'
	printf 'RAM: %s, SWAP: %s\n' "${ram[3]}" "${swap[3]}"
	printf '%s\n' '***'
	printf '%s\n' 'AVAILABLE (kibibytes)'
	printf 'RAM: %s\n\n' "${ram[6]}"

# If available RAM is less than 1GB...
	if [[ ${ram[6]} -lt $ram_limit ]]; then
# If Firefox / Tor Browser is running, then kill it, print a message to
# the screen, and append a message to the log.
		kill_firefox

# If Chrome / Chromium is running, then kill it, print a message to the
# screen, and append a message to the log.
		kill_chromium

# Writes cached writes to disk. Hopefully this will also clear up a
# little RAM.
		sync
	fi
done
