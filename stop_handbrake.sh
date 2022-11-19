#!/bin/bash
# This script finds a running HandBrake process, if it exists, and
# pauses it. The user can resume the process later with the
# 'start_handbrake.sh' script.

# The script uses the SIGSTP (20) signal to suspend the process.
# To get a list of available signals: kill -l

comm='HandBrakeCLI'

regex_pid_comm='^[[:space:]]*([[:digit:]]+)[[:space:]]*(.*)$'

mapfile -t hb_pids < <(ps -C "$comm" -o pid,args | tail -n +2)

for (( i = 0; i < ${#hb_pids[@]}; i++ )); do
	if [[ ${hb_pids[${i}]} =~ $regex_pid_comm ]]; then
		pid="${BASH_REMATCH[1]}"
		args="${BASH_REMATCH[2]}"

		cat <<INFO

STOPPING!
PID: ${pid}
COMMAND: ${args}

Run this command later to resume:
start_handbrake.sh

INFO

		kill -s 20 "$pid"
	fi
done
