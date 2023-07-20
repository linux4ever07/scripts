#!/bin/bash

# This script is meant to remove old kernel versions from Fedora. It
# automatically figures out what the latest installed version is for
# each kernel package, and removes all the older versions.

# If the script isn't run with sudo / root privileges, quit.
if [[ $EUID -ne 0 ]]; then
	printf '\n%s\n\n' 'You need to be root to run this script!'
	exit
fi

declare dnf_pkgs_n arch pause_msg version current latest_tmp
declare -a types keep remove
declare -A dnf_pkgs latest regex

types=('core' 'devel' 'devel_matched' 'headers' 'kernel' 'modules' 'modules_extra')

regex[column]="^(.*${arch}) (.*) (@.*) *$"
regex[version]='^([0-9]+)\.([0-9]+)\.([0-9]+)\-([0-9]+)\.fc[0-9]+'

regex[core]="^kernel\-core\.${arch}$"
regex[devel]="^kernel\-devel\.${arch}$"
regex[devel_matched]="^kernel\-devel\-matched\.${arch}$"
regex[headers]="^kernel\-headers\.${arch}$"
regex[kernel]="^kernel\.${arch}$"
regex[modules]="^kernel\-modules\.${arch}$"
regex[modules_extra]="^kernel\-modules\-extra\.${arch}$"

dnf_pkgs_n=0

arch='x86_64'
pause_msg='Does this look OK? [y/n]: '

# Creates a function called 'version_compare'. It finds out which
# version number passed to it is the most recent.
version_compare () {
	version_array=("$@")

	declare newest
	declare -a num newest_num

	for version_tmp in "${version_array[@]}"; do
		if [[ ! $version_tmp =~ ${regex[version]} ]]; then
			continue
		fi

		num=("${BASH_REMATCH[@]:1}")

		if [[ -z $newest ]]; then
			newest="$version_tmp"
			newest_num=("${num[@]}")
			continue
		fi

# This loop goes through each number, and first checks if the number is
# lower than the previous version that was checked. If it is, then break
# the loop. Since it's checking the numbers from left to right, if a
# version is older, one of the first numbers is going to be lower, even
# if one of the later numbers may be higher.
		for (( z = 0; z < ${#num[@]}; z++ )); do
			if [[ ${num[${z}]} -lt ${newest_num[${z}]} ]]; then
				break
			fi

			if [[ ${num[${z}]} -gt ${newest_num[${z}]} ]]; then
				newest="$version_tmp"
				newest_num=("${num[@]}")
				break
			fi
		done
	done

	printf '%s' "$newest"
}

mapfile -t lines < <(dnf list --installed | grep -E '^kernel' | sed -E 's/[[:blank:]]+/ /g')

# This loop gets the package name and version from each line, and saves
# that in the 'dnf_pkgs' hash.
for (( i = 0; i < ${#lines[@]}; i++ )); do
	line="${lines[${i}]}"

	if [[ ! $line =~ ${regex[column]} ]]; then
		continue
	fi

	match=("${BASH_REMATCH[@]:1}")

	dnf_pkgs["${dnf_pkgs_n},pkg"]="${match[0]}"
	dnf_pkgs["${dnf_pkgs_n},ver"]="${match[1]}"
	dnf_pkgs_n=$(( dnf_pkgs_n + 1 ))
done

unset -v lines

# This loop finds out what the latest version is for each kernel
# package.
for (( i = 0; i < dnf_pkgs_n; i++ )); do
	match=("${dnf_pkgs[${i},pkg]}" "${dnf_pkgs[${i},ver]}")

	for type in "${types[@]}"; do
		if [[ ! ${match[0]} =~ ${regex[${type}]} ]]; then
			continue
		fi

		if [[ ${match[1]} =~ ${regex[version]} ]]; then
			hash_ref="latest[${match[0]}]"

			if [[ -z ${!hash_ref} ]]; then
				latest["${match[0]}"]="${match[1]}"
			else
				version=$(version_compare "${!hash_ref}" "${match[1]}")
				latest["${match[0]}"]="$version"
			fi
		fi

		break
	done
done

# This loop decides which kernel packages will be kept, and which will
# be removed.
for (( i = 0; i < dnf_pkgs_n; i++ )); do
	match=("${dnf_pkgs[${i},pkg]}" "${dnf_pkgs[${i},ver]}")

	dnf_pkg="${match[0]%.${arch}}-${match[1]}.${arch}"

	for type in "${types[@]}"; do
		if [[ ! ${match[0]} =~ ${regex[${type}]} ]]; then
			continue
		fi

		hash_ref="latest[${match[0]}]"

		if [[ ${match[1]} == "${!hash_ref}" ]]; then
			keep+=("$dnf_pkg")
		else
			remove+=("$dnf_pkg")
		fi

		break
	done
done

# If there's no kernel packages older than the currently running
# version, quit.
if [[ ${#remove[@]} -eq 0 ]]; then
	printf '\n%s\n\n' 'Nothing to do!'
	exit
fi

current=$(uname -r)
latest_tmp="${latest[kernel.${arch}]}.${arch}"

# If the user does not have the latest installed kernel loaded, ask them
# to reboot before running the script.
if [[ $current != "$latest_tmp" ]]; then
	cat <<RUNNING

Current running kernel:
${current}

Latest installed kernel:
${latest_tmp}

You need to reboot before running this script, so the latest kernel can
be loaded. It might also be a good idea to install system updates before
that, so you're running the latest kernel that's available in the repos.

RUNNING

	exit
fi

printf '\n%s\n\n' 'These packages will be kept:'

printf '%s\n' "${keep[@]}"

printf '\n%s\n\n' 'These packages will be removed:'

printf '%s\n' "${remove[@]}"

printf '\n'

# Asks the user for confirmation.
read -p "$pause_msg"

if [[ $REPLY != 'y' ]]; then
	exit
fi

# Removes the packages.
for (( i = 0; i < ${#remove[@]}; i++ )); do
	dnf_pkg="${remove[${i}]}"
	dnf -y remove "$dnf_pkg"
done
