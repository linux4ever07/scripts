#!/bin/bash

# This script is meant to read a Bash script, and show variables that
# are used within functions, but haven't been formally declared within
# that same function. However, the script only goes 1 level deep, hence
# functions within functions will all be considered as 1 entity.

# Creates a function, called 'usage', which will print usage
# instructions and then quit.
usage () {
	printf '\n%s\n\n' "Usage: $(basename "$0") [file]"
	exit
}

if [[ ! -f $1 ]]; then
	usage
fi

if=$(readlink -f "$1")

declare switch_func switch_var
declare -a lines
declare -A regex

regex[start]="^([[:blank:]]*)([^ ]+)[[:blank:]]*\(\) \{"
regex[blank]='^[[:blank:]]*(.*)[[:blank:]]*$'
regex[declare]='^(declare|local)( -[[:alpha:]]+){0,1} (.*)$'
regex[var]='^([a-zA-Z0-9_]+)=(.*)$'
regex[mapfile]='^mapfile( -d.{3}){0,1}( -t){0,1} ([^ ]+).*$'

switch_func=0

mapfile -t lines < <(tr -d '\r' <"$if")

printf '\n'

for (( i = 0; i < ${#lines[@]}; i++ )); do
	line="${lines[${i}]}"
	line_tmp="$line"

	if [[ $line =~ ${regex[start]} && $switch_func -eq 0 ]]; then
		switch_func=1

		declare func_name
		declare -a declared undeclared

		func_name="${BASH_REMATCH[2]}"
		regex[stop]="^${BASH_REMATCH[1]}\}"
	fi

	if [[ $switch_func -eq 0 ]]; then
		continue
	fi

	if [[ $line_tmp =~ ${regex[blank]} ]]; then
		line_tmp="${BASH_REMATCH[1]}"
	fi

	if [[ $line_tmp =~ ${regex[declare]} ]]; then
		mapfile -d' ' -t declared_tmp <<<"${BASH_REMATCH[3]}"
		declared_tmp[-1]="${declared_tmp[-1]%$'\n'}"

		declared+=("${declared_tmp[@]}")
	fi

	if [[ $line_tmp =~ ${regex[var]} ]]; then
		var="${BASH_REMATCH[1]}"

		switch_var=0

		for (( j = 0; j < ${#declared[@]}; j++ )); do
			var_tmp="${declared[${j}]}"

			if [[ $var_tmp == "$var" ]]; then
				switch_var=1
				break
			fi
		done

		if [[ $switch_var -eq 0 ]]; then
			for (( j = 0; j < ${#undeclared[@]}; j++ )); do
				var_tmp="${undeclared[${j}]}"

				if [[ $var_tmp == "$var" ]]; then
					switch_var=1
					break
				fi
			done

			if [[ $switch_var -eq 0 ]]; then
				undeclared+=("$var")
			fi
		fi
	fi

	if [[ $line_tmp =~ ${regex[mapfile]} ]]; then
		var="${BASH_REMATCH[3]}"

		switch_var=0

		for (( j = 0; j < ${#declared[@]}; j++ )); do
			var_tmp="${declared[${j}]}"

			if [[ $var_tmp == "$var" ]]; then
				switch_var=1
				break
			fi
		done

		if [[ $switch_var -eq 0 ]]; then
			for (( j = 0; j < ${#undeclared[@]}; j++ )); do
				var_tmp="${undeclared[${j}]}"

				if [[ $var_tmp == "$var" ]]; then
					switch_var=1
					break
				fi
			done

			if [[ $switch_var -eq 0 ]]; then
				undeclared+=("$var")
			fi
		fi
	fi

	if [[ $line =~ ${regex[stop]} && $switch_func -eq 1 ]]; then
		switch_func=0

		if [[ ${#undeclared[@]} -gt 0 ]]; then
			printf '*** %s ***\n' "$func_name"
			printf '%s\n' "${undeclared[@]}"

			printf '\n'
		fi

		unset -v func_name declared undeclared
	fi
done
