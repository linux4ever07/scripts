#!/bin/bash

# This script is meant to replace echo commands in Bash scripts, with
# printf. 'echo' is an external command, while 'printf' is a Bash
# built-in. Hence this can have a performance impact, especially if
# the script is printing lots of text to the terminal or to files.

# There's still a need to go through the output script file manually
# after having run it through this script. Because the string that was
# passed to 'echo' in the input file might have newlines in it. Those
# newlines need to be added to the '%s' part of the printf command, and
# removed from the string.

# Also, depending on the use case of the original echo commands, the
# '\n', in the '%s' part of the printf command might not be necessary.
# Such as when passing strings between functions.

# The output script file replaces the input file.

if [[ ! -f $1 ]]; then
	printf '\n%s\n\n' "Usage: $(basename "$0") [file]"
	exit
fi

if=$(readlink -f "$1")

regex1='^([[:blank:]]*)#'
regex2='echo( \-[[:alpha:]]+){0,}[[:blank:]]*'
regex3='printf '\''%s\\n'\'' '

mapfile -t lines < <(tr -d '\r' <"$if")

for (( i = 0; i < ${#lines[@]}; i++ )); do
	line="${lines[${i}]}"

	if [[ $line =~ $regex1 ]]; then
		continue
	fi

	if [[ $line =~ $regex2 ]]; then
		lines["${i}"]=$(sed -E "s/${regex2}/${regex3}/g" <<<"$line")
	fi
done

truncate -s 0 "$if"

printf '%s\n' "${lines[@]}" > "$if"
