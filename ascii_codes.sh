#!/bin/bash

# This script converts a string from ASCII to decimal, octal and
# hexadecimal codes.

# To convert the character from decimal, octal or hexadecimal back to
# ASCII:
# printf '%b\n' '\x41'

# Type conversion specifiers for 'printf':
# %s string
# %d decimal
# %o octal
# %x hexadecimal

declare string char
declare -a array

# Creates a function, called 'usage', which will print usage
# instructions and then quit.
usage () {
	printf '\n%s\n\n' "Usage: $(basename "$0") [string]"
	exit
}

if [[ $# -eq 0 ]]; then
	usage
fi

string="$@"

# The loop below breaks the string up into its separate characters, and
# stores them in an array.
for (( i = 0; i < ${#string}; i++ )); do
	array+=("${string:${i}:1}")
done

# The loop below prints the characters in the following formats:
# %s string
# %d decimal
# %o octal
# %x hexadecimal
for (( i = 0; i < ${#array[@]}; i++ )); do
	char="${array[${i}]}"

	printf 'char: %-10s dec: %-10d oct: %-10o hex: %x\n' "$char" \'"$char" \'"$char" \'"$char"
done | less
