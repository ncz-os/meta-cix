#!/bin/sh
#
# cix_resume_prepare.sh - mount rootfs rw if no swsuspend resume.
#
# Runs at sysinit.target via cix_resume_prepare.service.  If the kernel
# cmdline has resume=<UUID|PARTUUID|...> AND the partition matching that
# identifier is actually formatted as Linux swap (swsuspend), exit 0
# without doing anything (the kernel will resume from it later).
#
# Otherwise (no resume= OR no matching swap partition), remount the root
# filesystem read-write so the system can boot normally -- the kernel
# mounts root RO by default and we only want RW if we're NOT resuming.
#
# Robust against the "no swap partition configured" case (e.g. O6N BIOS
# 1.0 boards where swsuspend is not provisioned): we just exit 0 without
# trying to swapon a non-existent partition, so the systemd service
# succeeds cleanly.
#
# IMPORTANT: do NOT pass btrfs-specific mount options here.  On btrfs
# rootfs the kernel only accepts btrfs mount options listed in
# fs/btrfs/super.c btrfs_fs_parameters[] -- `nodelalloc` is NOT one of
# them (it's a mkfs-time option, removed in btrfs-progs ~2019).  Passing
# an unknown btrfs mount option triggers:
#
#   btrfs: Unknown parameter 'nodelalloc'
#
# which is noisy in dmesg and historically made the remount fail too
# (which then made this script exit non-zero, surfacing as
# `cix_resume_prepare.service: Failed with result 'exit-code'`).
#
# This is the corrected version, suitable for both btrfs and ext4 rootfs.

for x in $(cat /proc/cmdline); do
	case $x in
	resume=*)
		echo "resume"
		RESUME="${x#resume=}"
		case $RESUME in
		UUID=*)
			RESUME="${RESUME#UUID=}"
			echo "cmdline has uuid"
			echo $RESUME
			;;
		PARTUUID=*)
			RESUME="${RESUME#PARTUUID=}"
			echo "cmdline has part uuid"
			echo $RESUME
			;;
		esac
		;;
	esac
done

# If we have a resume target AND it's actually a swsuspend partition, we're
# resuming -- do NOT touch the root mount, the kernel will resume from it.
if [ -n "$RESUME" ] && blkid | grep -q "$RESUME" && blkid | grep "$RESUME" | grep -q swsuspend; then
	echo "find std img"
	exit 0
fi

echo "no std img"

# No swsuspend resume target.  Re-enable swap on the resume partition if
# one exists (so the system has swap if $RESUME pointed at something,
# even if it's not swsuspend-formatted).  Skip silently if there's no
# matching partition -- common on boards without a swap partition.
if [ -n "$RESUME" ]; then
	swapPart=`blkid | grep "$RESUME" | sed 's/:.*//' | head -n1`
	if [ -n "$swapPart" ]; then
		echo "swap partition: $swapPart"
		swapon "$swapPart" || echo "swapon failed (non-fatal)"
	else
		echo "no swap partition matching $RESUME -- skipping swapon"
	fi
fi

echo "remount rootfs rw"
# `mount -o remount,rw` is sufficient on both ext4 and btrfs; the kernel
# already knows the existing mount options from the original mount and
# just flips RW.  Do NOT re-specify filesystem-specific options here --
# they may have changed across kernel versions and listing the wrong
# ones triggers a noisy "Unknown parameter" warning and (for btrfs)
# can fail the entire remount.
mount -o remount,rw / / || echo "remount,rw failed (non-fatal)"

exit 0
