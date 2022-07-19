#!/bin/bash
# This script is meant to remove old kernel versions from Fedora.

arch='x86_64'
regex='^[0-9]+\.[0-9]+'
pause_msg='Does this look OK? [y/n]: '

declare -a remove

# If the script isn't run with sudo / root privileges, quit.
if [[ $(whoami) != root ]]; then
	printf '%s\n\n' "You need to be root to run this script!"
	exit
fi

mapfile -t kernels < <(dnf list --installed | grep -E '^kernel' | grep -F -e "kernel.${arch}" -e "-core.${arch}" -e "-headers.${arch}" -e "-modules.${arch}" -e "-modules-extra.${arch}" | sed "s/[[:space:]]\+/ /g")

printf '\n%s\n' "This will remove kernel versions older than the one selected."
printf '%s\n\n' "Select the latest kernel version in the list:"

select kernel in "${kernels[@]}"; do
	latest=$(cut -d' ' -f2 <<<"$kernel")
	break
done

version=$(grep -Eo "$regex" <<<"$latest")

printf '\n%s\n\n' "These packages will be kept:"

for (( i = 0; i < ${#kernels[@]}; i++ )); do
	kernel="${kernels[${i}]}"
	if [[ $kernel =~ $version ]]; then
		printf '%s\n' "$kernel"
	fi
done

printf '\n%s\n\n' "These packages will be removed:"

for (( i = 0; i < ${#kernels[@]}; i++ )); do
	kernel="${kernels[${i}]}"
	if [[ ! $kernel =~ $version ]]; then
		printf '%s\n' "$kernel"
		remove+=("$kernel")
	fi
done

printf '\n'

if [[ "${#remove[@]}" -eq 0 ]]; then
	printf '%s\n\n' "Nothing to do!"
	exit
fi

read -p "$pause_msg"

case "$REPLY" in
	'y')
		for (( i = 0; i < ${#remove[@]}; i++ )); do
			mapfile -d' ' -t line <<<"${remove[${i}]}"
			line[0]=$(sed "s/\.${arch}$//" <<<"${line[0]}")
			kernel="${line[0]}-${line[1]}.${arch}"

			dnf -y remove "$kernel"
		done
	;;
	'*')
		break
	;;
esac
