#!/bin/bash

# This script is meant for conky. It uses vnstat to display network
# stats. First argument should be network device, and second argument
# either 'today' or 'month'.

mapfile -d';' -t vnstat < <(vnstat -i "$1" --oneline)

today="${vnstat[5]}"
month="${vnstat[10]}"

case "$2" in
	'today')
		printf '%s\n' "$today"
	;;
	'month')
		printf '%s\n' "$month"
	;;
esac
