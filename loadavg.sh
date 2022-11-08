#!/bin/bash

# This script is meant for conky. It displays load averages, divided by
# the number of CPUs.

cores=$(grep -c '^processor' '/proc/cpuinfo')
mapfile -d' ' -t loadavg <'/proc/loadavg'

load_1min=$(printf '%s/%s\n' "${loadavg[0]}" "$cores" | bc -l)
load_5min=$(printf '%s/%s\n' "${loadavg[1]}" "$cores" | bc -l)
load_15min=$(printf '%s/%s\n' "${loadavg[2]}" "$cores" | bc -l)

printf '%s %s %s\n' "${load_1min:0:4}" "${load_5min:0:4}" "${load_15min:0:4}"
