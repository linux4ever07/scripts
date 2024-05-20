#!/bin/bash

# This script is meant to remove old kernel versions from Fedora. It
# automatically figures out what the latest installed version is for
# each kernel package, and removes all the older versions.

# If the script isn't run with sudo / root privileges, quit.
if [[ $EUID -ne 0 ]]; then
	printf '\n%s\n\n' 'You need to be root to run this script!'
	exit
fi

declare dnf_pkgs_n dnf_pkg arch pause_msg line current latest_tmp type
declare -a match types lines versions_in versions_out keep remove
declare -A dnf_pkgs latest regex

dnf_pkgs_n=0

arch='x86_64'
pause_msg='Does this look OK? [y/n]: '

types=('core' 'devel' 'devel_matched' 'headers' 'kernel' 'modules' 'modules_extra')

regex[column]="^([^ ]+${arch}) ([^ ]+) ([^ ]+)"
regex[version]='^([0-9]+)\.([0-9]+)\.([0-9]+)-([0-9]+)\.fc[0-9]+'

regex[core]="^kernel-core\.${arch}$"
regex[devel]="^kernel-devel\.${arch}$"
regex[devel_matched]="^kernel-devel-matched\.${arch}$"
regex[headers]="^kernel-headers\.${arch}$"
regex[kernel]="^kernel\.${arch}$"
regex[modules]="^kernel-modules\.${arch}$"
regex[modules_extra]="^kernel-modules-extra\.${arch}$"

# Creates a function, called 'parse_version', which will parse a version
# number and print the result.
parse_version () {
	if [[ ! $1 =~ ${regex[version]} ]]; then
		exit
	fi

	printf '%s\n' "${BASH_REMATCH[@]:1}"
}

# Creates a function, called 'sort_versions', which will sort a list of
# version numbers from latest to oldest.
sort_versions () {
	declare in out
	declare -a num_in num_out

	while [[ ${#versions_in[@]} -gt 0 ]]; do
		out=0

		mapfile -t num_out < <(parse_version "${versions_in[0]}")

		for (( y = 1; y < ${#versions_in[@]}; y++ )); do
			in="${versions_in[${y}]}"

			mapfile -t num_in < <(parse_version "$in")

# This loop goes through each number, and checks if the number is lower
# or higher than the previous version that was checked.
			for (( z = 0; z < ${#num_in[@]}; z++ )); do
				if [[ ${num_in[${z}]} -lt ${num_out[${z}]} ]]; then
					break
				fi

				if [[ ${num_in[${z}]} -gt ${num_out[${z}]} ]]; then
					out="$y"
					num_out=("${num_in[@]}")

					break
				fi
			done
		done

		versions_out+=("${versions_in[${out}]}")

		unset -v versions_in["${out}"]
		versions_in=("${versions_in[@]}")
	done
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

	(( dnf_pkgs_n += 1 ))
done

unset -v lines

# This loop finds out what the latest version is for each kernel
# package.
for type in "${types[@]}"; do
	versions_in=()
	versions_out=()

	for (( i = 0; i < dnf_pkgs_n; i++ )); do
		match=("${dnf_pkgs[${i},pkg]}" "${dnf_pkgs[${i},ver]}")

		if [[ ! ${match[0]} =~ ${regex[${type}]} ]]; then
			continue
		fi

		versions_in+=("${match[1]}")
	done

	sort_versions

	latest["${type}"]="${versions_out[0]}"
done

# This loop decides which kernel packages will be kept, and which will
# be removed.
for type in "${types[@]}"; do
	for (( i = 0; i < dnf_pkgs_n; i++ )); do
		match=("${dnf_pkgs[${i},pkg]}" "${dnf_pkgs[${i},ver]}")

		dnf_pkg="${match[0]%.${arch}}-${match[1]}.${arch}"

		if [[ ! ${match[0]} =~ ${regex[${type}]} ]]; then
			continue
		fi

		if [[ ${match[1]} == "${latest[${type}]}" ]]; then
			keep+=("$dnf_pkg")
		else
			remove+=("$dnf_pkg")
		fi
	done
done

# If there's no kernel packages older than the currently running
# version, quit.
if [[ ${#remove[@]} -eq 0 ]]; then
	printf '\n%s\n\n' 'Nothing to do!'
	exit
fi

current=$(uname -r)
latest_tmp="${latest[kernel]}.${arch}"

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
