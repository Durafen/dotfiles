#!/bin/bash
# Run from bashrc, but work as non-invasive as possible
#  * Silently fail (2>/dev/null)
#  * Only if $TMUX is not set (equivalent to only new SSH sessions)
#  * Only automatically launch tmux if one session with no clients
#  * Any key will cancel the message


# DYNAMIC MOTD which centers in screen. Must be run in a terminal, so normal
# MOTD generation not possible.

# http://parkersamp.com/2010/10/howto-creating-a-dynamic-motd-in-linux/

# get true dimensions. tput works, but not if fish is parent shell on fish config.
eval $(resize)

function center {
	while read; do
		printf "%*s\n" $(((${#REPLY}+$COLUMNS)/2)) "$REPLY"
	done
}

if [ $(uname) != Linux ]; then
	echo 'Only Linux is supported at the moment' >&2
	# OSX problems: figlet, sed, read. Not worth it.
	exit
fi

if [ $COLUMNS -lt 148 ]; then
	echo Terminal not wide enough >&2
	exit 2
fi

if ! which figlet &>/dev/null; then
	echo "Install figlet first" >&2
	exit 127
fi

# clear screen (AKA reset terminal)
echo -ne  "\033c"

# hide cursor
echo -ne "\e[?25l"

# clearing screen sometimes leaves bits of last command, blank it
echo "                                                                                "

# white
echo -ne "\033[37m"

PADDING=$(($(($LINES-24))/2))

for i in $(seq 1 $PADDING); do
	echo
done

# ascii art hostname
#hostname -s | tr a-z A-Z | figlet -ctf slant
#hostname -s | tr a-z A-Z | figlet -ct
#hostname -s | tr a-z A-Z | figlet -ctf roman
#hostname -s | tr a-z A-Z | figlet -ctf univers.flf
#hostname -s | tr a-z A-Z | figlet -Wctf colossal.flf
#echo BLACKMESA | tr a-z A-Z | figlet -Wctf univers.flf
#echo BLACKMESA | tr a-z A-Z | figlet -Wctf colossal.flf
#hostname -s | tr a-z A-Z | figlet -ctf slant
#hostname -s | tr a-z A-Z | toilet -F border -f future
#hostname -s | tr a-z A-Z | toilet -F border:crop -f future
#hostname -s | tr a-z A-Z | figlet -ctf roman

# figlet -t is broken on mac os x. Try -w instead.
hostname -s | sed 's/.*/\u&/' | figlet -cf roman -w $COLUMNS


# domain name, double spaced. capital, centered
hostname -d | sed 's/./& /g' | tr a-z A-Z | center

# Always reset terminal, regardless of termination reason
function CLEANUP_EXIT {
	# show cursor
	echo -ne "\e[?25h"
	# reset terminal
	echo -ne  "\033c"
}
trap CLEANUP_EXIT EXIT


echo
if [ -r /etc/quotes ]; then
	echo; echo
	cat /etc/quotes | sort -R | tail -n 1 \
		| sed 's/.*/"&"/g' \
		| fold -w 76 -s \
		| center

	# extra pause if there is a quote
	read -n1 -t 1.2 && exit
fi

# wait for up to 1.2 seconds for any character
# Abortable sleep
read -n1 -t 1.2


