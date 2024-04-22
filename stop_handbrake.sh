#!/bin/bash

# This script finds running HandBrakeCLI processes, if they exist, and
# pauses them. The user can resume them later with the
# 'start_handbrake.sh' script.

# The script uses the SIGSTP (20) signal to suspend the process.
# To get a list of available signals: kill -l

declare comm pid args state
declare -a hb_pids
declare -A regex

comm='HandBrakeCLI'

regex[pid_comm]='^[[:blank:]]*([0-9]+)[[:blank:]]*(.*)$'

mapfile -t hb_pids < <(ps -C "$comm" -o pid=,args=)

for (( i = 0; i < ${#hb_pids[@]}; i++ )); do
	if [[ ! ${hb_pids[${i}]} =~ ${regex[pid_comm]} ]]; then
		continue
	fi

	pid="${BASH_REMATCH[1]}"
	args="${BASH_REMATCH[2]}"

	state=$(ps -p "$pid" -o state=)

	if [[ $state == 'T' ]]; then
		continue
	fi

	cat <<INFO

STOPPING!
PID: ${pid}
COMMAND: ${args}

Run this command later to resume:
start_handbrake.sh

INFO

	kill -s 20 "$pid"
done
