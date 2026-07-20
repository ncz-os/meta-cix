#!/bin/sh

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
                esac
                ;;
	esac
done
[[ `blkid | grep $RESUME | grep swsuspend` ]] && echo "find std img" && exit 0
blkid
echo "no std img"
swapPart=`blkid | grep $RESUME | sed 's/:.*//'`
echo $swapPart
swapon $swapPart
echo "remount rootfs rw"
mount -o remount,nodelalloc,rw / /
