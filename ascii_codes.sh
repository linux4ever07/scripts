#!/bin/bash

# This script converts a string from ASCII to decimal, octal and
# hexadecimal codes.

# https://www.gnu.org/software/bash/manual/html_node/ANSI_002dC-Quoting.html
# https://www.gnu.org/software/coreutils/manual/html_node/printf-invocation.html

# To convert the character back to ASCII (note the escape sequences)...

# Decimal:
# printf '%o\n' '65'
# printf '%b\n' '\101'

# Or...

# printf '%x\n' '65'
# printf '%b\n' '\x41'

# Octal:
# printf '%b\n' '\101'

# Hexadecimal:
# printf '%b\n' '\x41'

# Type conversion specifiers for 'printf':
# %s string
# %d decimal
# %o octal
# %x hexadecimal

declare string char

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
# prints the characters in the following formats:
# %s string
# %d decimal
# %o octal
# %x hexadecimal
for (( i = 0; i < ${#string}; i++ )); do
	char="${string:${i}:1}"

	printf 'char: %-10s dec: %-10d oct: %-10o hex: %x\n' "$char" \'"$char" \'"$char" \'"$char"
done | less
