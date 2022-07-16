#!/bin/bash
# This script is meant to remove old kernel versions from Fedora.

arch='x86_64'
regex='^[0-9]+\.[0-9]+'
pause_msg='Does this look OK? [y/n]: '

declare -a remove

# If the script isn't run with sudo / root privileges, then ask the user
# to type his / her password, so we can run the script with full root
# privileges. 'exec' is used in conjunction with 'sudo bash', thereby
# replacing the current shell, and current instance of the script, with
# the new one that has full privileges.
if [[ $(whoami) != root ]]; then
	echo -e "You need to be root to run this script!\n"
	exit
fi

mapfile -t kernels < <(dnf list --installed | grep -E '^kernel' | grep -F -e "kernel.${arch}" -e "-core.${arch}" -e "-headers.${arch}" -e "-modules.${arch}" -e "-modules-extra.${arch}" | sed "s/[[:space:]]\+/ /g")

echo -e "\nThis will remove kernel versions older than the one selected."
echo -e "Select the latest kernel version in the list:\n"

select kernel in "${kernels[@]}"; do
	latest=$(cut -d' ' -f2 <<<"$kernel")
	break
done

version=$(grep -Eo "$regex" <<<"$latest")

echo -e "\nThese packages will be kept:\n"

for (( i = 0; i < ${#kernels[@]}; i++ )); do
	kernel="${kernels[${i}]}"
	if [[ $kernel =~ $version ]]; then
		echo "$kernel"
	fi
done

echo -e "\nThese packages will be removed:\n"

for (( i = 0; i < ${#kernels[@]}; i++ )); do
	kernel="${kernels[${i}]}"
	if [[ ! $kernel =~ $version ]]; then
		echo "$kernel"
		remove+=("$kernel")
	fi
done

echo -e "\n"

if [[ "${#remove[@]}" -eq 0 ]]; then
	echo -e "Nothing to do!\n"
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
