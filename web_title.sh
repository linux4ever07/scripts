#!/bin/bash

# Gets the title of a URL. Might be useful for IRC bots, as an example.

declare agent word
declare -a words
declare -A regex

regex[blank]='[[:blank:]]+'
regex[url]='^(http)(s)?:\/\/'
regex[title]='^.*<title>(.*)<\/title>.*$'

agent='Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36'

mapfile -d' ' -t words < <(sed -E "s/${regex[blank]}/ /g" <<<"$@")
words[-1]="${words[-1]%$'\n'}"

# This function gets a URL using cURL.
get_page () {
	curl --location --user-agent "$agent" --retry 10 --retry-delay 10 --connect-timeout 10 --silent "$1" 2>&-
}

for (( i = 0; i < ${#words[@]}; i++ )); do
	word="${words[${i}]}"

	if [[ ! $word =~ ${regex[url]} ]]; then
		continue
	fi

	get_page "$word" | sed -nE "s/${regex[title]}/\1/p" | head -n 1
done
