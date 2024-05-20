#!/bin/bash

# This script will generate a process ID list, based on the command name
# given as argument, and sort by RAM used. The child PID that uses the
# most RAM is killed.

# In short, the script kills the child process that's the biggest RAM
# hog.

set -eo pipefail

declare comm_tmp args_tmp pid_tmp ram_used_tmp key line
declare -A regex pids pids_ram

regex[pid_args]='^[[:blank:]]*([0-9]+)([[:blank:]]*)([^ ]+)(.*)$'
regex[ram_pid]='^(.*) (.*)$'
regex[kb]='^([0-9]+)K$'

# Creates a function, called 'usage', which will print usage
# instructions and then quit.
usage () {
	printf '\n%s\n\n' "Usage: $(basename "$0") [command]"
	exit
}

if [[ $# -eq 0 ]]; then
	usage
fi

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

# Creates a function, called 'get_ram', which will get the amount of RAM
# used (in kilobytes) by the PID given as argument.
get_ram () {
	declare ram_used
	declare -a cmd_stdout

	mapfile -d' ' -t cmd_stdout < <(pmap "$1" | tail -n 1 | sed -E 's/[[:blank:]]+/ /g')
	cmd_stdout[-1]="${cmd_stdout[-1]%$'\n'}"

	ram_used="${cmd_stdout[2]}"

	if [[ $ram_used =~ ${regex[kb]} ]]; then
		ram_used="${BASH_REMATCH[1]}"
	else
		return
	fi

	printf '%s' "$ram_used"
}

printf '\n'

for comm_tmp in "$@"; do
	for key in "${!pids_ram[@]}"; do
		unset -v pids_ram["${key}"]
	done

	get_pids "$comm_tmp"

	for pid_tmp in "${!pids[@]}"; do
		ram_used_tmp=$(get_ram "$pid_tmp")

		if [[ -z $ram_used_tmp ]]; then
			continue
		fi

		pids_ram["${pid_tmp}"]="$ram_used_tmp"
	done

	for pid_tmp in "${!pids_ram[@]}"; do
		ram_used_tmp="${pids_ram[${pid_tmp}]}"

		printf '%s %s\n' "$ram_used_tmp" "$pid_tmp"
	done | sort -n | tail -n 1 | while read line; do
		if [[ ! $line =~ ${regex[ram_pid]} ]]; then
			continue
		fi

		ram_used_tmp="${BASH_REMATCH[1]}"
		pid_tmp="${BASH_REMATCH[2]}"
		args_tmp="${pids[${pid_tmp}]}"

		printf 'comm: %s\n\nargs: %s\n\npid: %s\n\nram: %s\n\n' "$comm_tmp" "$args_tmp" "$pid_tmp" "$ram_used_tmp"

		kill -9 "$pid_tmp"
	done
done
