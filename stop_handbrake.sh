#!/bin/bash
# This script finds a running HandBrake process, if it exists, and
# pauses it. The user can resume the process later with the
# 'start_handbrake.sh' script.

# The script uses the SIGSTP (20) signal to suspend the process.
# To get a list of available signals: kill -l

pid_list_f='/dev/shm/handbrake_pid.txt'
touch "$pid_list_f"

comm='HandBrakeCLI'

mapfile -t pids < <(ps -C "$comm" -o comm,pid | tail -n +2)

for (( i = 0; i < ${#pids[@]}; i++ )); do
	mapfile -d' ' -t pid_info < <(sed -E 's/ +/ /' <<<"${pids[${i}]}")
	name=$(tr -d '[:blank:]' <<<"${pid_info[0]}")
	pid=$(tr -d '[:blank:]' <<<"${pid_info[1]}")

	if [[ $name == $comm ]]; then
		printf '\n%s\n' 'STOPPING!'
		printf '%s\n' "NAME: ${name} : PID: ${pid}"
		kill -s 20 "${pid}"

		printf '%s\n' "$pid" >> "$pid_list_f"

		printf '\n%s\n' 'Run this command later to resume:'
		printf '%s\n\n' "start_handbrake.sh"
	fi
done
