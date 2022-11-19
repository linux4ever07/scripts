#!/bin/bash

# This script either reinstalls every RPM package on the system, or
# verifies all RPMs to see which ones are broken, and reinstalls those.
# Run with either 'full' or 'verify' as an argument.

date=$(date "+%F")
txt="${HOME}/dnf_reinstall_${date}.txt"

declare mode

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
if [[ $(whoami) != 'root' ]]; then
	printf '\n%s\n\n' 'You need to be root to run this script!'
	exit
fi

dnf_install () {
	touch "$txt"

	for (( i = 0; i < ${#dnf_pkgs[@]}; i++ )); do
		rpm="${dnf_pkgs[${i}]}"

		dnf -y reinstall "$rpm"

		if [[ $? -eq 0 ]]; then
			printf '%s\n' "$rpm" >> "$txt"
		fi
	done
}

case "$mode" in
	'full')
		mapfile -t dnf_pkgs < <(dnf list --installed | sed -E 's/[[:blank:]]+/ /g' | cut -d' ' -f1)
		dnf_install
	;;
	'verify')
		mapfile -t dnf_pkgs < <(rpm -qf $(rpm -Va | sed -E 's|^.* /|/|') | sort -u)
		dnf_install
	;;
esac
