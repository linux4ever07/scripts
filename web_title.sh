#!/bin/bash

# Gets the title of a URL.

agent='Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/109.0.0.0 Safari/537.36'
regex='<title>(.*)<\/title>'

# This function gets a URL using cURL.
get_page () {
	curl --location --user-agent "$agent" --retry 10 --retry-delay 10 --connect-timeout 10 --silent "$1" 2>&-
}

get_page "$1" | grep -m 1 -Eo "$regex" | sed -E "s/${regex}/\1/"
