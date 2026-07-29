#!/bin/bash

#    This file is part of horOpenVario 
#    Copyright (C) 2017-2021  Kai Horstmann <horstmannkai@hotmail.com>
#
#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License along
#    with this program; if not, write to the Free Software Foundation, Inc.,
#    51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

LOOPDEV=`sudo losetup -f`
if test -z "$LOOPDEV"
then 
    echo "No loop device available. Stop."
    exit 1
else
    echo "Using loop device ${LOOPDEV}"
fi
sudo losetup ${LOOPDEV} sd.img || exit 1
sudo partprobe ${LOOPDEV}

sync
sudo mount -v -o defaults,noatime ${LOOPDEV}p2 sdcard 
sudo mount -v -o defaults,noatime ${LOOPDEV}p1 sdcard/boot
sync

# Mount the dynamic kernel managed file systems for a pleasant CHROOT experience
sudo mount -v -t sysfs sysfs sdcard/sys
sudo mount -v -t proc proc sdcard/proc
sudo mount -v -t devtmpfs udev sdcard/dev
sudo mount -v -t devpts devpts sdcard/dev/pts
