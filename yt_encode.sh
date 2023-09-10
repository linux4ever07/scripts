#!/bin/bash

# This simple script is meant to encode my YouTube videos (desktop /
# gameplay recordings) to AV1 (from FFV1 lossless video). YouTube has a
# file size limit of 256 GB. The quality produced by this script is
# virtually identical to lossless, but the files are a lot smaller,
# hence much quicker to upload.

# The source files were created with SimpleScreenRecorder and Audacity.

# The output audio format is FLAC, as that's what I use now when
# recording. Before that, I would use PCM (WAV).

# The script needs to be run with root priviliges in order to be able to
# run 'renice' to raise the priority of the ffmpeg process.

# FPS is optional. If not specified, the output will use the same
# framerate as the input. FPS can only be specified once, and it will
# be used for all input files.

# How to get information about the AV1 encoder:
# ffmpeg --help encoder=libsvtav1

# How to suspend and resume ffmpeg processes (hence pausing the script):
# killall -20 ffmpeg
# killall -18 ffmpeg

# If the script isn't run with sudo / root privileges, quit.
if [[ $EUID -ne 0 ]]; then
	printf '\n%s\n\n' 'You need to be root to run this script!'
	exit
fi

# Creates a function, called 'usage', which will print usage
# instructions and then quit.
usage () {
	printf '\n%s\n\n' "Usage: $(basename "$0") [fps] [mkv]"
	exit
}

if [[ $# -eq 0 ]]; then
	usage
fi

declare if of pid exit_status
declare -a files args1 args2 args3 args
declare -A regex

regex[fps]='^([0-9]+)(\.[0-9]+){0,1}$'

if [[ $1 =~ ${regex[fps]} ]]; then
	args2=(-r \""${1}"\")

	shift
fi

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

for (( i = 0; i < ${#files[@]}; i++ )); do
	if="${files[${i}]}"
	of="${if%.*}_av1.mkv"

# If there's any running ffmpeg processes, wait until they're finished
# to avoid oversaturating the CPU.
	while ps -C ffmpeg -o pid= >/dev/null; do
		sleep 1
	done

	args1=(ffmpeg -y -i \""${if}"\" -pix_fmt yuv420p10le)
	args3=(-c:a flac -c:v libsvtav1 -crf 20 \""${of}"\")

	if [[ ${#args2[@]} -gt 0 ]]; then
		args=("${args1[@]}" "${args2[@]}" "${args3[@]}")
	else
		args=("${args1[@]}" "${args3[@]}")
	fi

	eval "${args[@]}" &

	pid="$!"

	renice -n -20 -p "$pid"

	wait "$pid" 1>&- 2>&-

	exit_status="$?"

# If the encoding succeeded, copy file permissions and modification
# time from input file to output file, and then delete the input file.
	if [[ $exit_status -eq 0 ]]; then
		chown --reference="$if" "$of"
		chmod --reference="$if" "$of"
		touch -r "$if" "$of"

		rm -f "$if"
	else
		exit
	fi
done
