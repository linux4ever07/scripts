#!/bin/bash

# This script is meant to recursively repack all the found archives
# in the directories given as arguments, in 7zip ('.tar.7z'), to
# preserve HDD space.

# The script will also check which archives are identical (by creating
# an MD5 hash representing the extracted content), which archives have
# similar names, which archives are empty, corrupt and contain broken
# symlinks.

# Text files containing all this information will be created in the
# user's home directory, which may be /root depending on if the script
# was started from a root session or from a normal user session (using
# sudo).

# If the archive is corrupt and a zip file, the script will try to
# repair it, before repacking it. If it can't repair it, it won't
# repack.

# The TAR archive format doesn't use compression, but it preserves the
# integrity of the contained files (by being able to contain multiple
# files inside a single TAR file). The reason for putting TAR archives
# in 7zip archives is that the TAR archive can at a later point be
# compressed using a different format, without having to extract the TAR
# or accidentally change the content in any way.

# If an input archive is for example '.tar.gz', only the gzip part will
# be extracted, leaving the contained TAR archive untouched, before
# repacking as 7zip.

# A recent version of 'md5db_fast.pl' is required to be located in the
# same directory as this script.

# PS: This code is a bit janky right now. It's a work in progress...

set -o pipefail

# Creates a function, called 'usage', which will print usage
# instructions and then quit.
usage () {
	printf '\n%s\n\n' "Usage: $(basename "$0") [dirs...]"
	exit
}

# Creates a function, called 'check_cmd', which will be used to check if
# the necessary commands are installed.
check_cmd () {
	declare cmd_tmp name_tmp
	declare -a missing_pkg
	declare -A cmd

	cmd[dar]='dar'
	cmd[7za]='7zip'
	cmd[7z]='7zip'
	cmd[rar]='rar'
	cmd[cabextract]='cabextract'

	for cmd_tmp in "${!cmd[@]}"; do
		name_tmp="${cmd[${cmd_tmp}]}"

		command -v "$cmd_tmp" 1>&-

		if [[ $? -ne 0 ]]; then
			missing_pkg+=("${cmd_tmp} (${name_tmp})")
		fi
	done

	if [[ ${missing_pkg[@]} -gt 0 ]]; then
		cat <<CMD

The following commands are not installed:
$(printf '%s\n' "${missing_pkg[@]}")

Install them through your package manager.

In the case of 'rar', you can get the Linux version for free @
https://www.rarlab.com/download.htm

Put the 'rar' executable in ${HOME}/bin, and make sure that this
directory is in your PATH variable.

You can modify your PATH variable by editing ${HOME}/.bashrc, and adding
this line:

PATH="\${HOME}/bin:\${PATH}"

CMD
		exit
	fi
}

#if [[ $EUID -ne 0 ]]; then
#	printf '\n%s\n\n' 'You need to be root to run this script!'
#	exit
#fi

if [[ $# -eq 0 ]]; then
	usage
fi

declare arg
declare -a library

for arg in "$@"; do
	if [[ -d $arg ]]; then
		library+=("$(readlink -f "$arg")")
	fi
done

if [[ ${#library[@]} -eq 0 ]]; then
	usage
fi

check_cmd

declare mode session exit_status no_ext ext hash key
declare -a files files_tmp_in files_tmp_out empty symlinks corrupt_in corrupt_out
declare -a ext_list1 ext_list2 stdout_v
declare -A input output regex md5h

ext_list1=('.tar' '.tgz' '.tbz' '.tbz2' '.txz')
ext_list2=('.z' '.gz' '.bz2' '.xz' '.zip' '.7z' '.rar' '.lzh' '.lha' '.arj')

regex[dev]='^\/dev'
regex[fn]='^(.*)\.([^.]*)$'
regex[abc]='[^a-zA-Z]'
regex[file]='^([^\/]+).*$'
regex[tar]='^\.tar\.[^.]*$'
regex[dar]='^\.[[:digit:]]+\.dar$'

input[fn_md5db]='md5.db'

input[dn_script]=$(dirname "$(readlink -f "$0")")

PATH="${input[dn_script]}:${PATH}"

session="${RANDOM}-${RANDOM}"

output[fn_same_md5]="${HOME}/repack_same_md5-${session}.txt"
output[fn_same_name]="${HOME}/repack_same_name-${session}.txt"
output[fn_corrupt]="${HOME}/repack_corrupt-${session}.txt"
output[fn_empty]="${HOME}/repack_empty-${session}.txt"
output[fn_symlink]="${HOME}/repack_symlink-${session}.txt"

# Trap signals (INT, TERM) and call iquit.
trap iquit SIGINT SIGTERM

iquit () {
	rm_tmp

	exit
}

# Creates a function, called 'output', which will let the user know if
# the command succeeded or not. If not, print the entire output from
# the compression program.
output () {
	exit_status="${stdout_v[-1]}"
	unset -v stdout_v[-1]

	if [[ $exit_status == '0' ]]; then
		printf '\n%s: %s\n' "$1" 'Everything is Ok'
	else
		printf '\n%s: %s\n' "$1" 'Something went wrong'

		printf '%s\n' "${stdout_v[@]}"

		if [[ $mode == 'pack' ]]; then
			exit
		fi
	fi
}

# Creates a function, called 'get_ext', which will separate file names
# and extensions.
get_ext () {
	declare -a ext_list

	no_ext="$1"

	while [[ $no_ext =~ ${regex[fn]} ]]; do
		no_ext="${BASH_REMATCH[1]}"
		ext_list=("${BASH_REMATCH[2],,}" "${ext_list[@]}")

		if [[ ${#ext_list[@]} -eq $2 ]]; then
			break
		fi
	done

	ext=$(printf '.%s' "${ext_list[@]}")
}

# Creates a function, called 'set_names', which will create variables
# for file names.
set_names () {
	declare switch

	switch=0

	input[fn]=$(readlink -f "$1")
	input[dn]=$(dirname "${input[fn]}")
	input[bn]=$(basename "${input[fn]}")

	get_ext "${input[bn]}" 2

	if [[ $ext =~ ${regex[tar]} ]]; then
		switch=1
	fi

	if [[ $ext =~ ${regex[dar]} ]]; then
		switch=1
	fi

	if [[ $switch -eq 0 ]]; then
		get_ext "${input[bn]}" 1
	fi

	output[bn_tmp]="${no_ext}-${RANDOM}"
	output[dn_tmp]="${input[dn]}/${output[bn_tmp]}"

	output[dn_tar]="${output[dn_tmp]}/tar"

	output[fn]="${input[dn]}/${no_ext}.tar.7z"

	if [[ -f ${output[fn]} && ${output[fn]} != "${input[fn]}" ]]; then
		output[fn]="${input[dn]}/${output[bn_tmp]}.tar.7z"
	fi

	output[fn_tmp]="${output[dn_tmp]}/${no_ext}"
}

# Creates a function, called 'get_files', which will get all the
# archives in the directories given as arguments to the script.
get_files () {
	declare ext_tmp
	declare -a files1 files2 files_all

	mapfile -t files_all < <(find "${library[@]}" -type f 2>&-)

	files=()

	for (( z = 0; z < ${#files_all[@]}; z++ )); do
		set_names "${files_all[${z}]}"

		for ext_tmp in "${ext_list1[@]}"; do
			regex[ext]="${ext_tmp}$"

			if [[ $ext =~ ${regex[ext]} ]]; then
				files1+=("${input[fn]}")
				break
			fi
		done

		for ext_tmp in "${ext_list2[@]}"; do
			regex[ext]="${ext_tmp}$"

			if [[ $ext =~ ${regex[ext]} ]]; then
				files2+=("${input[fn]}")
				break
			fi
		done
	done

	files=("${files1[@]}" "${files2[@]}")
}

# Creates a function, called 'get_symlinks', which will be used to find
# broken symlinks.
get_symlinks () {
	declare -a symlinks_tmp

	mapfile -t files_tmp_out < <(find . -mindepth 1 2>&-)

	for (( z = 0; z < ${#files_tmp_out[@]}; z++ )); do
		input[fn_test]="${files_tmp_out[${z}]}"

		if [[ ! -e ${input[fn_test]} ]]; then
			symlinks_tmp+=("${input[fn_test]}")
		fi
	done

	if [[ ${#symlinks_tmp[@]} -gt 0 ]]; then
		symlinks+=("*** ${output[fn]}" "${symlinks_tmp[@]}" '')
	fi

	files_tmp_out=()
}

# Creates a function, called 'sort_long', which will sort a list of file
# names from long to short.
sort_long () {
	declare length min_length max_length
	declare -a lengths_tmp

	min_length="${#files_tmp_in[0]}"
	max_length="${#files_tmp_in[0]}"

	for (( z = 0; z < ${#files_tmp_in[@]}; z++ )); do
		input[fn]="${files_tmp_in[${z}]}"
		input[bn]=$(basename "${input[fn]}")

		length="${#input[bn]}"

		lengths_tmp+=("$length")

		if [[ $length -lt $min_length ]]; then
			min_length="$length"
		fi

		if [[ $length -gt $max_length ]]; then
			max_length="$length"
		fi
	done

	if [[ $min_length -gt 0 ]]; then
		(( min_length -= 1 ))
	fi

	for (( y = max_length; y > min_length; y-- )); do
		length="$y"

		for (( z = 0; z < ${#files_tmp_in[@]}; z++ )); do
			input[fn]="${files_tmp_in[${z}]}"
			input[length]="${lengths_tmp[${z}]}"

			if [[ ${input[length]} -eq $length ]]; then
				printf '%s\n' "${input[fn]}"
			fi
		done
	done
}

# Creates a function, called 'arch_unpack', which will extract an
# archive.
arch_unpack () {
	mode='unpack'

	case "$1" in
		*.dar)
			mapfile -t stdout_v < <(dar -x "${output[fn_tmp]}" 2>&1; printf '%s\n' "$?")
			output "$2"
		;;
		*.tar)
			mapfile -t stdout_v < <(tar -xf "$2" 2>&1; printf '%s\n' "$?")
			output "$2"
		;;
		*.z|*.gz|*.tgz)
			mapfile -t stdout_v < <(gunzip "$2" 2>&1; printf '%s\n' "$?")
			output "$2"
		;;
		*.bz2|*.tbz|*.tbz2)
			mapfile -t stdout_v < <(bunzip2 "$2" 2>&1; printf '%s\n' "$?")
			output "$2"
		;;
		*.xz|*.txz)
			mapfile -t stdout_v < <(unxz "$2" 2>&1; printf '%s\n' "$?")
			output "$2"
		;;
		*.zip)
			mapfile -t stdout_v < <(unzip "$2" 2>&1; printf '%s\n' "$?")
			output "$2"
		;;
		*.7z)
			mapfile -t stdout_v < <(7za x "$2" 2>&1; printf '%s\n' "$?")
			output "$2"
		;;
		*.rar)
			mapfile -t stdout_v < <(rar x "$2" 2>&1; printf '%s\n' "$?")
			output "$2"
		;;
		*.lzh|*.lha)
			mapfile -t stdout_v < <(7z x "$2" 2>&1; printf '%s\n' "$?")
			output "$2"
		;;
		*.cab|*.exe)
			mapfile -t stdout_v < <(cabextract "$2" 2>&1; printf '%s\n' "$?")
			output "$2"
		;;
		*.arj)
			mapfile -t stdout_v < <(7z x "$2" 2>&1; printf '%s\n' "$?")
			output "$2"
		;;
		*)
			exit_status=1
		;;
	esac
}

# Creates a function, called 'arch_repair', which will try to repair
# corrupt archives.
arch_repair () {
	declare type

	type=$(file --brief --extension "${input[bn]}")

	if [[ $type =~ ${regex[file]} ]]; then
		type="${BASH_REMATCH[1]}"

		if [[ $type != '???' ]]; then
			ext="${ext%.*}.${type}"

			mv -n "${input[bn]}" "${no_ext}${ext}"

			input[bn]="${no_ext}${ext}"

			arch_unpack "$ext" "${output[fn_tmp]}${ext}"

			if [[ $exit_status -eq 0 ]]; then
				return
			fi

			rm_tmp "${output[fn_tmp]}${ext}"
		fi
	fi

	if [[ $ext == '.zip' ]]; then
		zip -q -F "${input[bn]}" --out "${output[bn_tmp]}.zip" 1>&- 2>&-
		arch_unpack "$ext" "${output[fn_tmp]}.zip"

		if [[ $exit_status -eq 0 ]]; then
			mv "${output[bn_tmp]}.zip" "${input[bn]}"
		else
			rm_tmp "${output[fn_tmp]}${ext}"

			zip -q -FF "${input[bn]}" --out "${output[bn_tmp]}.zip" 1>&- 2>&-
			arch_unpack "$ext" "${output[fn_tmp]}.zip"

			if [[ $exit_status -eq 0 ]]; then
				mv "${output[bn_tmp]}.zip" "${input[bn]}"
			fi
		fi
	fi
}

# Creates a function, called 'arch_pack', which will create an archive.
arch_pack () {
	mode='pack'

	if [[ ! -f "${no_ext}.tar" ]]; then
		mapfile -t stdout_v < <(tar -cf "${no_ext}.tar" "$@" 2>&1; printf '%s\n' "$?")
		output "${output[fn_tmp]}.tar"
	fi

	if [[ -f "${no_ext}.tar" ]]; then
		chown "${USER}:${USER}" "${no_ext}.tar"
		chmod ugo+rw-x "${no_ext}.tar"
	fi

	mapfile -t stdout_v < <(7za a -t7z -m0=lzma -mx=9 -mfb=64 -md=32m -ms=on "${no_ext}.tar.7z" "${no_ext}.tar" 2>&1; printf '%s\n' "$?")
	output "${output[fn_tmp]}.tar.7z"

	if [[ -f "${no_ext}.tar.7z" ]]; then
		chown "${USER}:${USER}" "${no_ext}.tar.7z"
		chmod ugo+rw-x "${no_ext}.tar.7z"
	fi
}

# Creates a function, called 'check_n_repack', which will get an MD5
# hash representing the extracted directory, and compress the directory
# content as a 7zip archive.
check_n_repack () {
	declare type hash

	if [[ $ext == '.tar' ]]; then
		rm_tmp "${output[fn_tmp]}${ext}"
	else
		rm -f "${input[bn]}"
	fi

	mapfile -t files_tmp_in < <(compgen -G "*")

	for (( z = 0; z < ${#files_tmp_in[@]}; z++ )); do
# The if statement below is only for my personal needs, and it can
# safely be removed.
		if [[ ${files_tmp_in[${z}]} == 'not a tty' ]]; then
			continue
		fi

		files_tmp_out+=("${files_tmp_in[${z}]}")
	done

	files_tmp_in=("${files_tmp_out[@]}")
	files_tmp_out=()

	if [[ ${#files_tmp_in[@]} -eq 1 && -f ${files_tmp_in[0]} ]]; then
		type=$(file --brief --extension "${files_tmp_in[0]}")

		if [[ $type =~ ${regex[file]} ]]; then
			type="${BASH_REMATCH[1]}"

			if [[ $type == 'tar' ]]; then
				mv -n "${files_tmp_in[0]}" "${no_ext}.tar"

				mapfile -t files_tmp_in < <(compgen -G "*")

				mkdir -p "${output[dn_tar]}"
				cd "${output[dn_tar]}"

				arch_unpack '.tar' "${output[fn_tmp]}.tar"
			fi
		fi
	fi

	get_symlinks

	md5db_fast.pl -index . 1>&- 2>&-

	if [[ -f ${input[fn_md5db]} ]]; then
		hash=$(md5sum -b "${input[fn_md5db]}")
		hash="${hash%% *}"

		md5h["${hash}"]+="${output[fn]}\n"
	else
		empty+=("${output[fn]}")
	fi

	if [[ $PWD == "${output[dn_tar]}" ]]; then
		cd "${output[dn_tmp]}"
		rm -rf "${output[dn_tar]}"
	fi

	arch_pack "${files_tmp_in[@]}"

	rm -f "${input[fn]}"
	mv "${no_ext}.tar.7z" "${output[fn]}"
}

# Creates a function, called 'rm_tmp', which will remove temporary
# files.
rm_tmp () {
	if [[ -z ${output[dn_tmp]} || ! -d ${output[dn_tmp]} ]]; then
		return
	fi

	if [[ $# -eq 0 ]]; then
		rm -rf "${output[dn_tmp]}"

		return
	fi

	declare switch
	declare -a skip

	skip=("$@")

	mapfile -t files_tmp_out < <(find "${output[dn_tmp]}" -mindepth 1 2>&-)

	for (( y = 0; y < ${#files_tmp_out[@]}; y++ )); do
		input[fn_test]="${files_tmp_out[${y}]}"

		for (( z = 0; z < ${#skip[@]}; z++ )); do
			output[fn_test]="${skip[${z}]}"

			switch=0

			if [[ ${input[fn_test]} ==  "${output[fn_test]}" ]]; then
				switch=1
				break
			fi
		done

		if [[ $switch -eq 0 ]]; then
			rm -rf "${input[fn_test]}"
		fi
	done

	files_tmp_out=()
}

# Creates a function, called 'get_common', which will check a list of
# file names and find the directory that has the most files.
get_common () {
	declare hash key common_n
	declare -A common_md5 common_dirs

	unset -v output[common_dn]

	for (( z = 0; z < ${#files_tmp_in[@]}; z++ )); do
		set_names "${files_tmp_in[${z}]}"

		hash=$(md5sum -b <<<"${input[dn]}")
		hash="${hash%% *}"

		(( common_md5[${hash}] += 1 ))

		common_dirs["${hash}"]="${input[dn]}"
	done

	if [[ ${#common_dirs[@]} -eq 1 ]]; then
		return
	fi

	for key in "${!common_dirs[@]}"; do
		input[dn]="${common_dirs[${key}]}"

		if [[ ${common_md5[${key}]} -gt $common_n ]]; then
			common_n="${common_md5[${key}]}"
			output[common_dn]="${input[dn]}"
		fi
	done
}

# Check and repack archives that aren't 7zip...
get_files

for (( i = 0; i < ${#files[@]}; i++ )); do
	set_names "${files[${i}]}"

	mkdir -p "${output[dn_tmp]}"
	cp -p "${input[fn]}" "${output[dn_tmp]}"
	cd "${output[dn_tmp]}"

	arch_unpack "$ext" "${output[fn_tmp]}${ext}"

	if [[ $exit_status -eq 0 ]]; then
		check_n_repack
	else
		corrupt_in+=("${input[fn]}")
	fi

	rm_tmp
done

# Try to repair broken archives, and then repack them as 7zip...
for (( i = 0; i < ${#corrupt_in[@]}; i++ )); do
	set_names "${corrupt_in[${i}]}"

	mkdir -p "${output[dn_tmp]}"
	cp -p "${input[fn]}" "${output[dn_tmp]}"
	cd "${output[dn_tmp]}"

	arch_repair

	if [[ $exit_status -eq 0 ]]; then
		check_n_repack
	else
		corrupt_out+=("${input[fn]}")
	fi

	rm_tmp
done

printf '%s\n' "${corrupt_out[@]}" > "${output[fn_corrupt]}"

unset -v corrupt_in corrupt_out

# Print duplicate MD5 hashes...
for key in "${!md5h[@]}"; do
	mapfile -t files_tmp_in < <(printf '%b' "${md5h[${key}]}" | sort)

	if [[ ${#files_tmp_in[@]} -eq 1 ]]; then
		continue
	fi

	mapfile -t files_tmp_in < <(sort_long "${files_tmp_in[@]}")

	printf '*** %s\n' "$key" >> "${output[fn_same_md5]}"

	for (( i = 0; i < ${#files_tmp_in[@]}; i++ )); do
		set_names "${files_tmp_in[${i}]}"

		printf '%s\n' "${input[fn]}" >> "${output[fn_same_md5]}"
	done

	printf '\n' >> "${output[fn_same_md5]}"
done

md5h=()

# Print duplicate archive names...
mapfile -t files < <(find "${library[@]}" -type f -iname "*.tar.7z" 2>&-)

for (( i = 0; i < ${#files[@]}; i++ )); do
	set_names "${files[${i}]}"

	input[bn_abc]=$(sed -E "s/${regex[abc]}//g" <<<"${no_ext,,}")
	input[bn_abc]="${input[bn_abc]:0:4}"

	hash=$(md5sum -b <<<"${input[bn_abc]}")
	hash="${hash%% *}"

	md5h["${hash}"]+="${input[fn]}\n"
done

for key in "${!md5h[@]}"; do
	mapfile -t files_tmp_in < <(printf '%b' "${md5h[${key}]}" | sort)

	if [[ ${#files_tmp_in[@]} -eq 1 ]]; then
		continue
	fi

	mapfile -t files_tmp_in < <(sort_long "${files_tmp_in[@]}")

	get_common

	if [[ -z ${output[common_dn]} ]]; then
		continue
	fi

	printf '*** %s\n' "${output[common_dn]}" >> "${output[fn_same_name]}"
	printf '%s\n' "${files_tmp_in[@]}" >> "${output[fn_same_name]}"
	printf '\n' >> "${output[fn_same_name]}"
done

unset -v md5h

# Print the rest of the text files.
printf '%s\n' "${empty[@]}" > "${output[fn_empty]}"
printf '%s\n' "${symlinks[@]}" > "${output[fn_symlink]}"
