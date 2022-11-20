#!/bin/bash

# This script starts / resumes HandBrakeCLI again, after it has been
# paused by 'stop_handbrake.sh'.

# The script uses the SIGCONT (18) signal to resume the process.
# To get a list of available signals: kill -l

comm='HandBrakeCLI'

regex_pid_comm='^[[:blank:]]*([[:digit:]]+)[[:blank:]]*(.*)$'

mapfile -t hb_pids < <(ps -C "$comm" -o pid,args | tail -n +2)

for (( i = 0; i < ${#hb_pids[@]}; i++ )); do
	if [[ ${hb_pids[${i}]} =~ $regex_pid_comm ]]; then
		pid="${BASH_REMATCH[1]}"
		args="${BASH_REMATCH[2]}"

		state=$(ps -p "$pid" -o state | tail -n +2)

		if [[ $state == 'R' ]]; then
			continue
		fi

		cat <<INFO

STARTING!
PID: ${pid}
COMMAND: ${args}

INFO

		kill -s 18 "$pid"
	fi
done
