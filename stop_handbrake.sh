#!/bin/bash
# This script finds a running HandBrake process, if it exists, and
# pauses it. The user can resume the process later by typing
# 'kill -s 18 $pid'.
# The script runs 'kill -s 20 $pid', to suspend the process.
# 20 = SIGSTP (kill -l)

pid_list_f='/dev/shm/handbrake_pid.txt'
touch "$pid_list_f"

comm='HandBrakeCLI'

mapfile -t pids < <(ps -C "$comm" -o comm,pid | tail -n +2)

for (( i = 0; i < ${#pids[@]}; i++ )); do
	mapfile -d' ' -t pid_info < <(sed 's/ \+/ /' <<<"${pids[${i}]}")
	name=$(tr -d '[:blank:]' <<<"${pid_info[0]}")
	pid=$(tr -d '[:blank:]' <<<"${pid_info[1]}")

	if [[ $name == $comm ]]; then
		printf '\n%s\n' 'STOPPING!'
		printf '%s\n' "NAME: ${name} : PID: ${pid}"
		kill -s 20 "${pid}"

		printf '%s\n' "$pid" >> "$pid_list_f"

# 18 = SIGCONT (kill -l)
		printf '\n%s\n' 'Run this command later to resume:'
		printf '%s\n\n' "start_handbrake.sh"
	fi
done

