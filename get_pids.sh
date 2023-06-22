#!/bin/bash

# This script gets all the child processes of the command names
# specified.

declare -A regex pids

regex[pid_args]='^[[:blank:]]*([0-9]+)([[:blank:]]*)([^ ]+)(.*)$'

# Creates a function called 'usage', which will print usage instructions
# and then quit.
usage () {
	printf '\n%s\n\n' "Usage: $(basename "$0") [name]"
	exit
}

# Creates a function called 'get_pids', which gets all child process IDs
# of the command names given to it as arguments.
get_pids () {
	declare pid args comm_path
	declare -a match

	for key in "${!pids[@]}"; do
		unset -v pids["${key}"]
	done

	for comm in "$@"; do
		unset -v pid args

		mapfile -t session < <(ps -C "$comm" -o sid= | tr -d '[:blank:]' | sort -u)

		if [[ ${#session[@]} -eq 0 ]]; then
			continue
		fi

		mapfile -t child < <(ps -H -s "${session[0]}" -o pid=,args=)

		for (( i = 0; i < ${#child[@]}; i++ )); do
			line="${child[${i}]}"

			if [[ $line =~ ${regex[pid_args]} ]]; then
				match=("${BASH_REMATCH[@]:1}")
				pid="${match[0]}"
				args="${match[2]}"

				if [[ $pid -eq ${session[0]} ]]; then
					continue
				fi

				args+="${match[3]}"
				pids["${pid}"]="$args"
			fi
		done
	done
}

get_pids "$@"

printf '\n'

for pid in "${!pids[@]}"; do
	printf 'PID: %s\n' "$pid"
	printf 'ARGS: %s\n\n' "${pids[${pid}]}"
done
