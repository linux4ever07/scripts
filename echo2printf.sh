#!/bin/bash

# This script is meant to replace 'echo' commands in Bash scripts, with
# 'printf'. Both echo and printf exist as Bash built-ins (as well as
# external commands). When they are run, the built-in takes precedence.

# I prefer to use printf over echo, as it's more flexible in my opinion.

# There's still a need to go through the output script file manually
# after having run it through this script. Because the string that was
# passed to 'echo' in the input file might have newlines in it. Those
# newlines need to be added to the '%s' part of the printf command, and
# removed from the string.

# Also, depending on the use case of the original echo commands, the
# '\n', in the '%s' part of the printf command might not be necessary.
# Such as when passing strings between functions.

# The output script file replaces the input file.

# Creates a function, called 'usage', which will print usage
# instructions and then quit.
usage () {
	printf '\n%s\n\n' "Usage: $(basename "$0") [file]"
	exit
}

if [[ ! -f $1 ]]; then
	usage
fi

declare if printf_cmd line
declare -a lines
declare -A regex

if=$(readlink -f "$1")

regex[comment]='^[[:blank:]]*#+'
regex[echo]='echo( -[[:alpha:]]+){0,}[[:blank:]]*'

printf_cmd='printf '\''%s\\n'\'' '

mapfile -t lines < <(tr -d '\r' <"$if")

for (( i = 0; i < ${#lines[@]}; i++ )); do
	line="${lines[${i}]}"

	if [[ $line =~ ${regex[comment]} ]]; then
		continue
	fi

	if [[ $line =~ ${regex[echo]} ]]; then
		lines["${i}"]=$(sed -E "s/${regex[echo]}/${printf_cmd}/g" <<<"$line")
	fi
done

truncate -s 0 "$if"

printf '%s\n' "${lines[@]}" > "$if"
