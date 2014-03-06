#!/bin/bash

# Builds darksky ubuntu (naggie/dotfiles based) which is a remastered live CD.
# See example grub.cfg in etc/ to boot from a flash drive.
# Uses current branch.

# Incremental approach, using an existing ISO.

# Use the 'toram' kernel parameter. The result is a super-fast, disposable
# environment! You'll need at least 3GB of RAM though.
#
# Based on https://help.ubuntu.com/community/LiveCDCustomization

# Modes of operation:
#
# 1. Source and Target non-existent: New source is downloaded, target is compiled
# 2. Target exists: Target is used as source
# 3. Just source exists: New target is created


# Install pre-requisities
#sudo apt-get install squashfs-tools genisoimage aufs-tools


# TODO: rename all mount points

cd $(dirname $0)
BRANCH=$(git rev-parse --abbrev-ref HEAD)
CHANGE=$(git rev-list HEAD --count)
NAME="darkbuntu-$BRANCH"

UBUNTU_ISO_URL='http://www.ubuntu.com/start-download?distro=desktop&bits=64&release=latest'
SOURCE='ubuntu-13.10-desktop-amd64.iso'
TARGET="$NAME.iso"

if [ $SUDO_USER ]; then
	LIVECD_USER=$SUDO_USER
else
	LIVECD_USER=$BRANCH
fi

function WARNING {
	# TODO: check PS1, no escape code if not interactive....?
	echo -e "\e[00;31m> $*\e[00m"
}

if [ `whoami` != root ]; then
	WARNING Run as root
	exit
fi

if [ -f "$TARGET" ]; then
	SOURCE="$TARGET"
	echo 'Incremental build'
elif [ ! -f "$SOURCE" ]; then
	echo 'Downloading initial ISO'
	wget "$UBUNTU_ISO_URL" -O "$SOURCE" || exit 2
fi

echo
echo SOURCE: $SOURCE
echo TARGET: $TARGET
echo
echo

# check dependencies
if ! which mkisofs mksquashfs &> /dev/null; then
	WARNING 'Error! required genisoimage and/or squashfs-tools package(s) are not installed'
	exit
fi

if [ $(uname -m) != x86_64 ]; then
	WARNING 'Error! x86_64 architecture required.'
	exit
fi

# less typing, with environment variables set
# HACK home dir = /etc/skel? so dbus-launch gsettings works.
# This will be copied to home dir of new user.
function INSIDE {
	chroot build/filesystem_rw \
		/usr/bin/env \
		HOME=/etc/skel \
		LC_ALL=C \
		USER=root \
		"$@"
}

function BREAKPOINT {
	INSIDE /bin/bash
}

# remove all trace of building in a safe way on termination
# might fail if things are not there yet, but that's fine.
function CLEANUP_EXIT {
	STATUS=$?
	# the following commands can fail, they must proceed
	set +e
	# -d always free loop device, prevent leaking them
	# TODO FIXME WARNING -l may leave a loop dev used
	sync
	# order is important: there are dependencies
	umount -l build/filesystem_rw/proc
	umount    build/filesystem_rw/sys
	umount -l build/filesystem_rw/dev
	umount    build/filesystem_rw/dev/pts
	umount -d build/iso_ro
	sync
	rm -rf build
	# TODO: check to see if dev is there before rm -rfing
	exit $STATUS
}

if [ -d build ]; then
	WARNING 'Stale build directory found. Refusing to build.'
	exit
else
	mkdir build
fi

# always clean up on CTRL+C (and anything, now)
#trap CLEANUP_EXIT SIGINT
trap CLEANUP_EXIT EXIT

# echo commands to aid debugging
set -x

# exit on error? NEEDS TRAP TO CLEANUP_EXIT
# use || true to skip exit-on-fail for single commands if inconsequential
# This is useful on an incremental build
set -e


mkdir build/iso_ro
mount -o loop,ro "$SOURCE" build/iso_ro

# extract ISO so files are writable
mkdir build/iso_rw
rsync --exclude=/casper/filesystem.squashfs -a build/iso_ro/ build/iso_rw

# Extract the Desktop system
# Extract the SquashFS filesystem
unsquashfs -no-progress -d build/filesystem_rw build/iso_ro/casper/filesystem.squashfs

# Prepare and chroot
# network connection within chroot
# Don't replace resolv.conf, overwrite it so that permissions don't change.
# This way, network manager can still work.
cat /etc/resolv.conf > build/filesystem_rw/etc/resolv.conf
cat /etc/hosts       > build/filesystem_rw/etc/hosts

# other filesystems, inside chroot
# these mount important directories of your host system - if you later decide to
# delete the edit/ directory, then make sure to unmount before doing so,
# otherwise your host system will become unusable at least temporarily until
# reboot)
# Also rm -rf'ing over binded dev really isn't a good thing...
mount -t proc   none build/filesystem_rw/proc
mount -t sysfs  none build/filesystem_rw/sys
mount -t devpts none build/filesystem_rw/dev/pts
mount --bind /dev/   build/filesystem_rw/dev

# hostname, username:
# <<- : no leading whitespace
# EOF in single quotes for no variable substitution
cat <<- EOF > build/filesystem_rw/etc/casper.conf
	export USERNAME=$LIVECD_USER
	export USERFULLNAME="Live session user"
	export HOST=darkbuntu-$CHANGE
	export BUILD_SYSTEM="Ubuntu"
	export FLAVOUR=Ubuntu # required to make above apply
EOF

# In 9.10, (+?) before installing or upgrading packages you need to run
# also may as well update/upgrade and add repositories
dbus-uuidgen | INSIDE tee /var/lib/dbus/machine-id
INSIDE dpkg-divert --local --rename --add /sbin/initctl
INSIDE ln -s /bin/true /sbin/initctl || true
INSIDE add-apt-repository universe
INSIDE add-apt-repository multiverse

INSIDE ln -s /lib/init/upstart-job /etc/init.d/whoopsie || true # required, otherwise apt breaks

yes | INSIDE apt-get update
yes | INSIDE apt-get install git


#BREAKPOINT

# install packages
# and dotfiles
# naggie/dotfiles does this all
# installs dotfiles to /etc/skel/ so that live (ubuntu) user will get a
#cp -a ../dotfiles build/filesystem_rw/root/
#git clone . build/filesystem_rw/root/dotfiles
# rsync preserves original origin and submodules, but git submodules have
# absolute references which break if you move the git folder on old versions of
# git...
#rsync -r --exclude=build --exclude='*iso' "$DOTFILES_DIR" build/filesystem_rw/root/dotfiles
# TODO try this instead
INSIDE git clone -b $BRANCH git://github.com/naggie/dotfiles.git /etc/skel/dotfiles || true
INSIDE /etc/skel/dotfiles/provision/ubuntu-13.10-desktop
INSIDE /etc/skel/dotfiles/install.sh

# edit variables in /etc/casper.conf for distro/host/username

# CLEANUP
# Be sure to remove any temporary files which are no longer needed, as space on a
# CD is limited. A classic example is downloaded package files, which can be
# cleaned out using:
yes | INSIDE apt-get upgrade # just in case it's not already done
yes | INSIDE apt-get clean
yes | INSIDE apt-get autoremove

# New kernel or initrd?
#cp build/filesystem_rw/boot/vmlinuz-2.6.15-26-k7    build/iso_rw/casper/vmlinuz
# new initrd generated when Broadcom sta drivers were installed.
cp build/filesystem_rw/boot/initrd.img* build/iso_rw/casper/initrd.lz
# After you've modified the kernel, init scripts or added new kernel
# modules, you need to rebuild the initrd.gz file and substitute it into
# the casper directory.
#INSIDE mkinitramfs -o /initrd.gz 2.6.15-26-k7
#mv edit/initrd.gz iso_rw-cd/casper/
# may need to convert to LZ gzip -dc initrd.gz | sudo lzma -7 > initrd.lz


# Utterly stupid hack required to fix keyboard map for installer on livecd.
# must be done last, otherwise clobbered by ubiquity update.
# .Xmodmap is used for live session. /etc/default/keyboard is the debian
# X/console keyboard main config file. `setxkbmap gb` would also work in
# session.
sed -i -re "s/'en': *'us',/'en': 'gb',/g" \
	build/filesystem_rw/usr/lib/ubiquity/ubiquity/misc.py

rm -rf build/filesystem_rw/tmp/*
rm     build/filesystem_rw/etc/skel/.bash_history || true # don't 'fail'

# RM/UMOUNT STUFF THAT SHOULDN'T BE IN FILESYSTEM IMAGE
rm build/filesystem_rw/etc/hosts
# overwrite, preserve permissions, see above.
echo > build/filesystem_rw/etc/resolv.conf

# Clean after installing software
rm build/filesystem_rw/var/lib/dbus/machine-id
rm build/filesystem_rw/sbin/initctl
INSIDE dpkg-divert --rename --remove /sbin/initctl

umount -l build/filesystem_rw/proc
umount    build/filesystem_rw/sys
umount -l build/filesystem_rw/dev
umount    build/filesystem_rw/dev/pts
umount    build/iso_ro

# ASSEMBLE ISO
chmod +w build/iso_rw/casper/filesystem.manifest

INSIDE dpkg-query -W --showformat='${Package} ${Version}\n' > build/iso_rw/casper/filesystem.manifest

cp build/iso_rw/casper/filesystem.manifest build/iso_rw/casper/filesystem.manifest-desktop

sed -i '/ubiquity/d' build/iso_rw/casper/filesystem.manifest-desktop
sed -i '/casper/d'   build/iso_rw/casper/filesystem.manifest-desktop

# COMPRESS FILESYSTEM
# already excluded by rsync (not any more now that aufs is used)
#rm build/iso_rw/casper/filesystem.squashfs

# For a highest possible compression at the cost of compression time, you may
# use the xz method and is better exclude the edit/boot directory altogether:
mksquashfs \
	build/filesystem_rw build/iso_rw/casper/filesystem.squashfs \
	-comp xz -e build/filesystem_rw/boot -no-progress \
	>/dev/null # buffering progress indicator might be a bottleneck... flag does not work

# Update the filesystem.size file, which is needed by the installer:
printf $(du -sx --block-size=1 build/filesystem_rw | cut -f1) > build/iso_rw/casper/filesystem.size

# Set an image name in extract-cd/README.diskdefines
#vim extract-cd/README.diskdefines

# recalc hashes
rm build/iso_rw/md5sum.txt
# subshell, no chdir persistence
echo 'Calculating hashes...'
(
	cd build/iso_rw
	find -type f -print0 \
		| xargs -0 md5sum \
		| grep -v isolinux/boot.cat \
		> md5sum.txt
)

# Create the ISO image
mkisofs -D -r -V "$NAME" -cache-inodes -J -l \
	-b isolinux/isolinux.bin \
	-c isolinux/boot.cat \
	-no-emul-boot -boot-load-size 4 \
	-boot-info-table \
	-o "$TARGET" build/iso_rw/

# clean, MUST MAKE SURE EVERYTHING IS UNMOUNTED FIRST, PARTICULARLY dev
# OR PREPARE FOR CORE MELTDOWN
# now umount (unmount) special filesystems before creation of iso
# This is handled by TRAP

# TODO? postprocess to allow simple dd to flash drive to work?
# isohybrid
# http://manpages.ubuntu.com/manpages/natty/man1/isohybrid.1.html


# TODO? modify isolinux so that default is toram (current use case uses grub on
# flash drive)

# TODO? EFI support for grub2+flash drive, so can boot on mac.


# Example: burn the image to CD with:
#cdrecord dev=/dev/cdrom ubuntu-9.04-desktop-i386-custom.iso

# Could order files to reduce seeking time, but not normally used from CD any more.
# http://lichota.net/~krzysiek/projects/kubuntu/dapper-livecd-optimization/

# To virtualise and test:

#sudo apt-get install qemu kvm
#sudo adduser naggie kvm
#qemu-system-x86_64 -m 1024 -usbdevice tablet -k en-gb -vnc :0,lossy -vga std -cdrom darkbuntu-naggie.iso
#
# After this, on an intermediate host
#
# forward port 5900, which is :0
#ssh -g -L 5900:localhost:5900 naggie@chell.darksky.io
#
#
# Then connect using a vncviewer. Performance is pretty much as if it was
# local due to kvm and vnc. The letdown is really the fancy effects making
# it slow.
# TODO: exit on error (with appropriate trap)
