#!/bin/bash

is_mounted()
{
    mountpoint -q "$1"
}

mnt()
{
    echo "MOUNTING"
    sudo mkdir -p "${2}/proc" "${2}/sys" "${2}/dev"

    is_mounted "${2}/proc" || sudo mount -t proc /proc "${2}/proc"
    is_mounted "${2}/sys" || sudo mount -t sysfs /sys "${2}/sys"
    is_mounted "${2}/dev" || sudo mount -o bind /dev "${2}/dev"
}

umount_one()
{
    if is_mounted "$1"; then
        sudo umount "$1" 2>/dev/null || sudo umount -l "$1"
    fi
}

umnt()
{
    echo "UNMOUNTING"
    umount_one "${2}/proc"
    umount_one "${2}/sys"
    umount_one "${2}/dev"
}

if [ "$1" == "-m" ] && [ -n "$2" ]; then
    mnt $1 $2
elif [ "$1" == "-u" ] && [ -n "$2" ]; then
    umnt $1 $2
else
    echo ""
    echo "Either 1'st, 2'nd or both parameters were missing"
    echo ""
    echo "1'st parameter can be one of these: -m(mount) OR -u(umount)"
    echo "2'nd parameter is the full path of rootfs directory"
    echo ""
    echo "For example: ch-mount.sh -m /media/sdcard"
    echo ""
    echo 1st parameter : ${1}
    echo 2nd parameter : ${2}
fi
