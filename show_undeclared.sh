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

declare if switch_func switch_var func_name var var_tmp line line_tmp
declare -a lines declared_tmp
declare -A regex declared_global undeclared_global

if=$(readlink -f "$1")

regex[start]='^([[:blank:]]*)([^ ]+)[[:blank:]]*\(\) \{'
regex[blank]='^[[:blank:]]*(.*)[[:blank:]]*$'
regex[declare]='^(declare|local)( -[[:alpha:]]+){0,1} (.*)$'
regex[var]='[a-zA-Z0-9_]+'
regex[var_set]="^(${regex[var]})(\[.*\]){0,1}=.*$"
regex[var_for]="^for (${regex[var]}) in .*; do$"
regex[mapfile]="^mapfile( -d.{3}){0,1}( -t){0,1} (${regex[var]}).*$"

switch_func=0

func_name='main'

mapfile -t lines < <(tr -d '\r' <"$if")

printf '\n%s\n\n' "$if"

# Handling global variables here.
for (( i = 0; i < ${#lines[@]}; i++ )); do
	line="${lines[${i}]}"
	line_tmp="$line"

	if [[ $line =~ ${regex[start]} && $switch_func -eq 0 ]]; then
		switch_func=1

		regex[stop]="^${BASH_REMATCH[1]}\}"
	fi

	if [[ $line =~ ${regex[stop]} && $switch_func -eq 1 ]]; then
		switch_func=0
	fi

	if [[ $switch_func -eq 1 ]]; then
		continue
	fi

	if [[ $line_tmp =~ ${regex[blank]} ]]; then
		line_tmp="${BASH_REMATCH[1]}"
	fi

	if [[ $line_tmp =~ ${regex[declare]} ]]; then
		mapfile -d' ' -t declared_tmp <<<"${BASH_REMATCH[3]}"
		declared_tmp[-1]="${declared_tmp[-1]%$'\n'}"

		for (( j = 0; j < ${#declared_tmp[@]}; j++ )); do
			var_tmp="${declared_tmp[${j}]}"
			declared_global["${var_tmp}"]=1
		done
	fi

	if [[ $line_tmp =~ ${regex[var_set]} || $line_tmp =~ ${regex[var_for]} ]]; then
		var="${BASH_REMATCH[1]}"

		switch_var=0

		for var_tmp in "${!declared_global[@]}"; do
			if [[ $var_tmp == "$var" ]]; then
				switch_var=1
				break
			fi
		done

		if [[ $switch_var -eq 0 ]]; then
			for var_tmp in "${!undeclared_global[@]}"; do
				if [[ $var_tmp == "$var" ]]; then
					switch_var=1
					break
				fi
			done

			if [[ $switch_var -eq 0 ]]; then
				undeclared_global["${var}"]=1
			fi
		fi
	fi

	if [[ $line_tmp =~ ${regex[mapfile]} ]]; then
		var="${BASH_REMATCH[3]}"

		switch_var=0

		for var_tmp in "${!declared_global[@]}"; do
			if [[ $var_tmp == "$var" ]]; then
				switch_var=1
				break
			fi
		done

		if [[ $switch_var -eq 0 ]]; then
			for var_tmp in "${!undeclared_global[@]}"; do
				if [[ $var_tmp == "$var" ]]; then
					switch_var=1
					break
				fi
			done

			if [[ $switch_var -eq 0 ]]; then
				undeclared_global["${var}"]=1
			fi
		fi
	fi
done

if [[ ${#undeclared_global[@]} -gt 0 ]]; then
	printf '*** %s ***\n' "$func_name"
	printf '%s\n' "${!undeclared_global[@]}" | sort
	printf '\n'
fi

unset -v func_name declared_global undeclared_global

# Handling local variables here.
for (( i = 0; i < ${#lines[@]}; i++ )); do
	line="${lines[${i}]}"
	line_tmp="$line"

	if [[ $line =~ ${regex[start]} && $switch_func -eq 0 ]]; then
		switch_func=1

		declare func_name
		declare -A declared_local undeclared_local

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

		for (( j = 0; j < ${#declared_tmp[@]}; j++ )); do
			var_tmp="${declared_tmp[${j}]}"
			declared_local["${var_tmp}"]=1
		done
	fi

	if [[ $line_tmp =~ ${regex[var_set]} || $line_tmp =~ ${regex[var_for]} ]]; then
		var="${BASH_REMATCH[1]}"

		switch_var=0

		for var_tmp in "${!declared_local[@]}"; do
			if [[ $var_tmp == "$var" ]]; then
				switch_var=1
				break
			fi
		done

		if [[ $switch_var -eq 0 ]]; then
			for var_tmp in "${!undeclared_local[@]}"; do
				if [[ $var_tmp == "$var" ]]; then
					switch_var=1
					break
				fi
			done

			if [[ $switch_var -eq 0 ]]; then
				undeclared_local["${var}"]=1
			fi
		fi
	fi

	if [[ $line_tmp =~ ${regex[mapfile]} ]]; then
		var="${BASH_REMATCH[3]}"

		switch_var=0

		for var_tmp in "${!declared_local[@]}"; do
			if [[ $var_tmp == "$var" ]]; then
				switch_var=1
				break
			fi
		done

		if [[ $switch_var -eq 0 ]]; then
			for var_tmp in "${!undeclared_local[@]}"; do
				if [[ $var_tmp == "$var" ]]; then
					switch_var=1
					break
				fi
			done

			if [[ $switch_var -eq 0 ]]; then
				undeclared_local["${var}"]=1
			fi
		fi
	fi

	if [[ $line =~ ${regex[stop]} && $switch_func -eq 1 ]]; then
		switch_func=0

		if [[ ${#undeclared_local[@]} -gt 0 ]]; then
			printf '*** %s ***\n' "$func_name"
			printf '%s\n' "${!undeclared_local[@]}" | sort

			printf '\n'
		fi

		unset -v func_name declared_local undeclared_local
	fi
done
