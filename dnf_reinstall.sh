#!/bin/bash

# This script either reinstalls every RPM package on the system, or
# verifies all RPMs to see which ones are broken, and reinstalls those.
# Run with either 'full' or 'verify' as an argument.

declare mode

# Creates a function, called 'usage', which will print usage
# instructions and then quit.
usage () {
	printf '\n%s\n\n' "Usage: $(basename "$0") [full|verify]"
	exit
}

case "$1" in
	'full')
		mode='full'
	;;
	'verify')
		mode='verify'
	;;
	*)
		usage
	;;
esac

# If the script isn't run with sudo / root privileges, quit.
if [[ $EUID -ne 0 ]]; then
	printf '\n%s\n\n' 'You need to be root to run this script!'
	exit
fi

declare date txt_fn
declare -a dnf_pkgs
declare -A regex

date=$(date '+%F')
txt_fn="${HOME}/dnf_reinstall_${date}.txt"

regex[dnf]='^([^ ]+).*$'
regex[rpm]='^[^\/]+(.*)$'

# Creates a function, called 'dnf_install', which will reinstall
# packages.
dnf_install () {
	declare rpm

	touch "$txt_fn"

	for (( i = 0; i < ${#dnf_pkgs[@]}; i++ )); do
		rpm="${dnf_pkgs[${i}]}"

		dnf -y reinstall "$rpm"

		if [[ $? -eq 0 ]]; then
			printf '%s\n' "$rpm" >> "$txt_fn"
		fi
	done
}

case "$mode" in
	'full')
		mapfile -t dnf_pkgs < <(dnf list --installed | sed -E "s/${regex[dnf]}/\1/")
		dnf_install
	;;
	'verify')
		mapfile -t dnf_pkgs < <(rpm -qf $(rpm -Va | sed -E "s/${regex[rpm]}/\1/") | sort -u)
		dnf_install
	;;
esac
