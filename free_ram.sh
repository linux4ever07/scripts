#!/bin/bash

# This script creates an infinite while loop, which checks the available
# RAM every 1 second, and kills Firefox, Chrome, Chromium and
# Tor Browser if less than 1 GB is available. The script will only kill
# the tabs, but not the main window itself, so the application keeps
# running but RAM is still freed up.

# The web browser is always the application that ends up using the most
# RAM on my system. Once the RAM is nearly full, Linux starts swapping
# and gradually slows down more and more, until grinding to a complete
# halt when RAM is completely full. Then Linux calls the Out Of Memory
# (OOM) manager to kill processes to free up RAM. It might kill a
# critical process, a program that's been running for a very long time
# (i.e. video encoding). To prevent that from happening, I created
# this script.

declare ram_limit log_killed
declare -a free_ram ram swap
declare -A regex pids

regex[pid_args]='^[[:blank:]]*([0-9]+)([[:blank:]]*)([^ ]+)(.*)$'
regex[rend]='--type=renderer'
regex[ext]='--extension-process'
regex[tab]='^.*-childID [0-9]+.* tab$'

# Creates a limit for the amount of free RAM required.
ram_limit=1000000

# Creates a file name for the log.
log_killed="${HOME}/browser_killed.log"

# If $log_killed is not a file, create it.
if [[ ! -f $log_killed ]]; then
	touch "$log_killed"
fi

# Creates a function, called 'now', which will print the date and time.
now () { date '+%F %H:%M:%S'; }

# Creates a function, called 'get_pids', which gets all child process
# IDs of the command names given to it as arguments.
get_pids () {
	declare key pid args comm comm_path bn line
	declare -a session child match

	for key in "${!pids[@]}"; do
		unset -v pids["${key}"]
	done

	for comm in "$@"; do
		unset -v pid args comm_path

		mapfile -t session < <(ps -C "$comm" -o sid= | tr -d '[:blank:]' | sort -u)

		if [[ ${#session[@]} -eq 0 ]]; then
			continue
		fi

		mapfile -t child < <(ps -H -s "${session[0]}" -o pid=,args=)

		for (( i = 0; i < ${#child[@]}; i++ )); do
			line="${child[${i}]}"

			if [[ ! $line =~ ${regex[pid_args]} ]]; then
				continue
			fi

			match=("${BASH_REMATCH[@]:1}")
			pid="${match[0]}"
			args="${match[2]}"

			bn=$(basename "$args")

			if [[ $bn == "$comm" ]]; then
				comm_path="$args"
				break
			fi
		done

		if [[ -z $comm_path ]]; then
			continue
		fi

		for (( i = 0; i < ${#child[@]}; i++ )); do
			line="${child[${i}]}"

			if [[ ! $line =~ ${regex[pid_args]} ]]; then
				continue
			fi

			match=("${BASH_REMATCH[@]:1}")
			pid="${match[0]}"
			args="${match[2]}"

			if [[ $pid -eq ${session[0]} ]]; then
				continue
			fi

			if [[ $args != "$comm_path" ]]; then
				continue
			fi

			args+="${match[3]}"
			pids["${pid}"]="$args"
		done
	done
}

# Creates a function, called 'kill_firefox', which kills all child
# processes belonging to either Firefox or Tor Browser.
kill_firefox () {
	declare time pid args
	declare -a pids_tmp

	get_pids 'firefox' 'firefox.real'
	mapfile -t pids_tmp < <(printf '%s\n' "${!pids[@]}" | sort -n)

	if [[ ${#pids_tmp[@]} -eq 0 ]]; then
		return
	fi

	time=$(now)
	printf '%s\n\n' "${time}: Killing Firefox / Tor Browser..." | tee --append "$log_killed"

	for (( i = 0; i < ${#pids_tmp[@]}; i++ )); do
		pid="${pids_tmp[${i}]}"
		args="${pids[${pid}]}"

# Checks if $pid is a renderer process.
		if [[ ! $args =~ ${regex[tab]} ]]; then
			continue
		fi

		printf '%s\n' "SIGKILL: ${pid}"
		kill -9 "$pid"
	done
}

# Creates a function, called 'kill_chrome', which kills all child
# processes belonging to either Chrome or Chromium.
kill_chrome () {
	declare time pid args
	declare -a pids_tmp

	get_pids 'chrome' 'chromium'
	mapfile -t pids_tmp < <(printf '%s\n' "${!pids[@]}" | sort -n)

	if [[ ${#pids_tmp[@]} -eq 0 ]]; then
		return
	fi

	time=$(now)
	printf '%s\n\n' "${time}: Killing Chrome / Chromium..." | tee --append "$log_killed"

	for (( i = 0; i < ${#pids_tmp[@]}; i++ )); do
		pid="${pids_tmp[${i}]}"
		args="${pids[${pid}]}"

# Checks if $pid is a renderer / extension process. If it's NOT a
# renderer, or is an extension process, skip it. This will keep
# extensions and downloads running, even though the other Chrome child
# processes are killed. Only renderer processes that are NOT extension
# processes will get killed.
		if [[ ! $args =~ ${regex[rend]} ]]; then
			continue
		elif [[ $args =~ ${regex[ext]} ]]; then
			continue
		fi

		printf '%s\n' "SIGKILL: ${pid}"
		kill -9 "$pid"
	done
}

# Creates an infinite while loop.
while [[ 1 ]]; do
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
		kill_chrome

# Writes cached writes to disk. Hopefully this will also clear up a
# little RAM.
		sync
	fi
done
