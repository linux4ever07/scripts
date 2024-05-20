#!/bin/bash

# This script will corrupt the files given to it as arguments, by
# writing zeroes to the end of the file. Don't use this script unless
# you want to lose the data in those files.

set -eo pipefail

declare -a files

# Creates a function, called 'usage', which will print usage
# instructions and then quit.
usage () {
	printf '\n%s\n\n' "Usage: $(basename "$0") [file 1] [file N]"
	exit
}

# The loop below handles the arguments to the script.
while [[ $# -gt 0 ]]; do
	if [[ -f $1 ]]; then
		files+=("$(readlink -f "$1")")
	else
		usage
	fi

	shift
done

if [[ ${#files[@]} -eq 0 ]]; then
	usage
fi

declare fn size_in size_out block_size seek count

# Creates a function, called 'block_calc', which will be used to get the
# optimal block size to use.
block_calc () {
	declare bytes1 bytes2 block_diff1 block_diff2

	bytes1="$1"
	bytes2="$2"

	block_size=1048576

	if [[ $block_size -gt $bytes2 ]]; then
		block_size="$bytes2"
	fi

	block_diff1=$(( bytes1 % block_size ))
	block_diff2=$(( bytes2 % block_size ))

	until [[ $block_diff1 -eq 0 && $block_diff2 -eq 0 ]]; do
		(( block_size -= 1 ))

		block_diff1=$(( bytes1 % block_size ))
		block_diff2=$(( bytes2 % block_size ))
	done
}

for (( i = 0; i < ${#files[@]}; i++ )); do
	fn="${files[${i}]}"

	size_in=$(stat -c '%s' "$fn")
	size_out=$(( size_in / 10 ))

	block_calc "$size_in" "$size_out"

	seek=$(( (size_in - size_out) / block_size ))
	count=$(( size_out / block_size ))

	printf '\n*** %s\n' "$fn"
	printf 'size: %s , block: %s , seek: %s , count: %s\n\n' "$size_in" "$block_size" "$seek" "$count"

	dd if='/dev/zero' of="$fn" bs="$block_size" seek="$seek" count="$count" &>/dev/null
done
