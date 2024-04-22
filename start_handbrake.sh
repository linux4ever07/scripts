#!/bin/bash

# This script starts / resumes HandBrakeCLI again, after it has been
# paused by 'stop_handbrake.sh'.

# The script uses the SIGCONT (18) signal to resume the process.
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

	if [[ $state != 'T' ]]; then
		continue
	fi

	cat <<INFO

STARTING!
PID: ${pid}
COMMAND: ${args}

INFO

	kill -s 18 "$pid"
done
