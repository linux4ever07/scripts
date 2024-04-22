#!/bin/bash

# This script prints all the subtitle languages of an MKV file
# in a comma-separated list. The MKV file should be given as the 1st
# argument to this script.

declare switch line
declare -a mkvinfo_tracks mkvinfo_lines lang_list
declare -A if regex tracks

if[fn]=$(readlink -f "$1")
if[bn]=$(basename "${if[fn]}")
if[bn_lc]="${if[bn],,}"

regex[start]='^\|\+ Tracks$'
regex[stop]='^\|\+ '
regex[strip]='^\| +\+ (.*)$'
regex[track]='^Track$'
regex[sub]='^Track type: subtitles$'
regex[lang]='^Language( \(.*\)){0,1}: (.*)$'
regex[name]='^Name: (.*)$'

# Creates a function, called 'usage', which will print usage
# instructions and then quit.
usage () {
	printf '\n%s\n\n' "Usage: $(basename "$0") [mkv]"
	exit
}

if [[ ! -f ${if[fn]} || ${if[bn_lc]##*.} != 'mkv' ]]; then
	usage
fi

command -v mkvinfo 1>&-

if [[ $? -ne 0 ]]; then
	printf '\nThis script needs %s installed!\n\n' 'mkvtoolnix'
	exit
fi

mapfile -t mkvinfo_lines < <(mkvinfo "${if[fn]}" 2>&-)

# Singles out the part that lists the tracks, and ignores the rest of
# the output from 'mkvinfo'.
switch=0

for (( i = 0; i < ${#mkvinfo_lines[@]}; i++ )); do
	line="${mkvinfo_lines[${i}]}"

	if [[ $line =~ ${regex[start]} ]]; then
		switch=1
		continue
	fi

	if [[ $switch -eq 0 ]]; then
		continue
	fi

	if [[ $line =~ ${regex[stop]} ]]; then
		switch=0
		break
	fi

	if [[ $line =~ ${regex[strip]} ]]; then
		line="${BASH_REMATCH[1]}"
	fi

	mkvinfo_tracks+=("$line")
done

unset -v mkvinfo_lines

# Gets all tracks from Matroska file.
declare n

for (( i = 0; i < ${#mkvinfo_tracks[@]}; i++ )); do
	line="${mkvinfo_tracks[${i}]}"

	if [[ $line =~ ${regex[track]} ]]; then
		if [[ -z $n ]]; then
			n=0
		else
			(( n += 1 ))
		fi

		tracks["${n},sub"]=0
	fi

	if [[ $line =~ ${regex[sub]} ]]; then
		tracks["${n},sub"]=1
	fi

# For some tracks, the language can be listed twice. First with a
# three-letter code, and then with a two-letter code. The first code is
# preferred by this script.
	if [[ $line =~ ${regex[lang]} ]]; then
		if [[ -z ${tracks[${n},lang]} ]]; then
			tracks["${n},lang"]="${BASH_REMATCH[2],,}"
		fi
	fi

	if [[ $line =~ ${regex[name]} ]]; then
		if [[ -z ${tracks[${n},name]} ]]; then
			tracks["${n},name"]="${BASH_REMATCH[1]}"
		fi
	fi
done

(( n += 1 ))

unset -v mkvinfo_tracks

# Creates a function, called 'sort_list', which will sort any subtitle
# tracks it finds in alphabetical order, and remove duplicates.
sort_list () {
	for (( i = 0; i < n; i++ )); do
		if [[ ${tracks[${i},sub]} -ne 1 ]]; then
			continue
		fi

		if [[ -n ${tracks[${i},lang]} ]]; then
			printf '%s\n' "${tracks[${i},lang]}"
		elif [[ -n ${tracks[${i},name]} ]]; then
			printf '%s\n' "${tracks[${i},name]}"
		fi
	done | sort -u
}

mapfile -t lang_list < <(sort_list)

unset -v n

printf 'Subtitles: '

for (( i = 0; i < ${#lang_list[@]}; i++ )); do
	line="${lang_list[${i}]}"

	if [[ $i -ne 0 ]]; then
		printf '%s' ', '
	fi

	if [[ -n $line ]]; then
		printf '%s' "${line^}"
	fi
done

printf '\n'
