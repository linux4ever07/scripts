#!/bin/bash

# This is just a simple script to send a signal to 'chrome_ram.sh' to
# restart Chrome. If it has stopped responding. This is to avoid having
# to access the hard drive, in case the intention was not to quit
# Chrome.

regex[bn]='google-chrome-[0-9]+-[0-9]+'
regex[ram]="^${regex[bn]}$"

mapfile -t files < <(find '/dev/shm' -mindepth 1 -maxdepth 1 -type d -name "google-chrome-*")

for (( i = 0; i < ${#files[@]}; i++ )); do
	fn="${files[${i}]}"
	bn=$(basename "$fn")

	if [[ ! $bn =~ ${regex[ram]} ]]; then
		continue
	fi

	touch "${fn}/kill"
done
