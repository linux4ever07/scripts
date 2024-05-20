#!/bin/bash

# This script gets all the processes that share the same session ID as
# the command names specified. Can be used to get all child processes
# of a command, for example. Note that command names are case sensitive.
# As an example, 'Xorg' will work, but 'xorg' will not.

# Creates a function, called 'usage', which will print usage
# instructions and then quit.
usage () {
	printf '\n%s\n\n' "Usage: $(basename "$0") [name]"
	exit
}

if [[ $# -eq 0 ]]; then
	usage
fi

declare comm_tmp pid
declare -a session name
declare -A regex pids

regex[pid_args]='^[[:blank:]]*([0-9]+)([[:blank:]]*)([^ ]+)(.*)$'

# Creates a function, called 'get_pids', which gets all child process
# IDs of the command names given to it as arguments.
get_pids () {
	declare key pid args comm comm_path line
	declare -a child match

	for key in "${!pids[@]}"; do
		unset -v pids["${key}"]
	done

	for comm in "$@"; do
		unset -v pid args

		mapfile -t session < <(ps -C "$comm" -o sid= | tr -d '[:blank:]' | sort -u)

		if [[ ${#session[@]} -eq 0 ]]; then
			continue
		fi

		mapfile -t name < <(ps -p "${session[0]}" -o args=)

		mapfile -t child < <(ps -H -s "${session[0]}" -o pid=,args=)

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

			args+="${match[3]}"
			pids["${pid}"]="$args"
		done
	done
}

for comm_tmp in "$@"; do
	get_pids "$comm_tmp"

	if [[ ${#pids[@]} -eq 0 ]]; then
		continue
	fi

	printf '\n***\n\n'

	printf 'SID: %s\n' "${session[0]}"
	printf 'ARGS: %s\n\n' "${name[0]}"

	for pid in "${!pids[@]}"; do
		printf 'PID: %s\n' "$pid"
		printf 'ARGS: %s\n\n' "${pids[${pid}]}"
	done

	printf '***\n\n'
done
