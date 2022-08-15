#!/bin/bash
# This script starts / resumes HandBrake again, after it has been paused
# by 'stop_handbrake.sh'.

# The script uses the SIGCONT (18) signal to resume the process.
# To get a list of available signals: kill -l

comm='HandBrakeCLI'
pid_list_f='/dev/shm/handbrake_pid.txt'

if [[ ! -f $pid_list_f ]]; then
		exit
fi

pid=$(head -n 1 "$pid_list_f")

if [[ -n $pid ]]; then
		name=$(ps -p "$pid" -o comm | tail -n +2)

		if [[ $name == $comm ]]; then
			printf '\n%s\n' 'STARTING!'
			printf '%s\n' "NAME: ${name} : PID: ${pid}"

			kill -s 18 "$pid"
		else
			exit
		fi
fi

mapfile -t pid_list < <(tail -n +2 "$pid_list_f")

truncate -s 0 "$pid_list_f"

if [[ -n ${pid_list[@]} ]]; then
		for (( i = 0; i < ${#pid_list[@]}; i++ )); do
				printf '%s\n' "${#pid_list[${i}]}" >> "$pid_list_f"
		done
fi
