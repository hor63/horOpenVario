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


# set -x

export LANG=C.UTF-8

cleanup_and_exit_error () {

echo "Unmount the SD card image"  
sync
sudo umount sdcard/sys
sudo umount sdcard/proc
sudo umount sdcard/dev/pts
sudo umount sdcard/dev
sudo umount sdcard/boot
sudo umount sdcard
sudo losetup -d /dev/loop5

exit 1
}

# Architecture of the target system
# Can be something like armhf, amd64, i386, arm64, s390 (haha)
# Must conform with existing Unbuntu architectures
if [ y$TARGETARCH = y ]
then
    TARGETARCH=armhf
fi

# According to the architecture I may need the emulator to be able to chroot into the
# new root.
case $TARGETARCH in
    armhf)
        EMULATOR=qemu-arm-static
        ARCH=arm
        BUILDDIR=build
        ;;
     i386)
        EMULATOR=qemu-i386-static
        ARCH=x86
        BUILDDIR=build.i386
        ;;
     arm64)
        EMULATOR=qemu-aarch64-static
        ARCH=arm64
        BUILDDIR=build.arm64
        ;;
     s390)
        EMULATOR=qemu-s390x-static
        ARCH=s390
        BUILDDIR=build.s390
        ;;
     *)
        echo "Error: \$TARGETARCH is undefined or invalid. \$TARGETARCH = \"$TARGETARCH\""
        exit 1
        ;;
    esac

no_pause=0
if test x"$1" = "x--no-pause"
then
	no_pause=1
fi

BASEDIR=`dirname $0`
BASEDIR="`(cd \"$BASEDIR\" ; BASEDIR=\`pwd\`; echo \"$BASEDIR\")`"
echo " BASEDIR = $BASEDIR"
export BASEDIR

cd $BASEDIR

./mountSDImage.sh

( 
  echo "Rebuild the kernel"

  # Make sure that there is no stale modules directory left.
  # I will derive the linux version from the modules directory name
  rm -rf $BUILDDIR/kernel/debian/*
  
  echo "Delete previous build artifacts"
  rm $BUILDDIR/* 2>/dev/null

  #echo "Clean the kernel"
  #  $BUILDDIR/kernel/build.sh clean
  
  if [ $TARGETARCH = armhf ]
  then
    $BUILDDIR/kernel/build.sh dtbs || exit 1
    echo "Copy the dtb"
    sudo cp -v $BUILDDIR/kernel/arch/arm/boot/dts/sun7i-a20-cubieboard2.dtb sdcard/boot
  fi # if [ $TARGETARCH = armhf ]

  echo "Build Debian kernel package"
  $BUILDDIR/kernel/build.sh -j8 bindeb-pkg || exit 1
  
) || cleanup_and_exit_error  

if [ -d build/kernel/debian/tmp/lib/modules ]
then
LINUX_VERSION=`basename $BUILDDIR/kernel/debian/tmp/lib/modules/*`
else
LINUX_VERSION=`basename $BUILDDIR/kernel/debian/linux-image/lib/modules/*`
fi
echo "LINUX_VERSION = $LINUX_VERSION"

if test $no_pause = 0
then
echo "Hit enter to continue"
read x
fi

if [ $TARGETARCH = armhf ]
then

    ( 
    echo "Build the Mali kernel module"
    cd src/sunxi-mali

    # Clean the structure and prepare for a new build in case of a previous failure
    CROSS_COMPILE=arm-linux-gnueabihf- KDIR=$BASEDIR/$BUILDDIR/kernel ./build.sh -r r8p1 -c >/dev/null 2>&1

    CROSS_COMPILE=arm-linux-gnueabihf- KDIR=$BASEDIR/$BUILDDIR/kernel ./build.sh -r r8p1 -b || exit 1

    ) || cleanup_and_exit_error

    if test $no_pause = 0
    then
    echo "Hit enter to continue"
    read x
    fi

    ( 
    echo "Install the Mali kernel module in the kernel DEB image"
    cd src/sunxi-mali

    if [ -d $BASEDIR/$BUILDDIR/kernel/debian/tmp ]
    then
        CROSS_COMPILE=arm-linux-gnueabihf- KDIR=$BASEDIR/$BUILDDIR/kernel INSTALL_MOD_PATH=$BASEDIR/$BUILDDIR/kernel/debian/tmp ./build.sh -r r8p1 -i || exit 1
    else
        CROSS_COMPILE=arm-linux-gnueabihf- KDIR=$BASEDIR/$BUILDDIR/kernel INSTALL_MOD_PATH=$BASEDIR/$BUILDDIR/kernel/debian/linux-image ./build.sh -r r8p1 -i || exit 1
    fi
    
    # undo the patches. Otherwise the next build will fail because applying the patches is part of the build option of build.sh
    CROSS_COMPILE=arm-linux-gnueabihf- KDIR=$BASEDIR/$BUILDDIR/kernel ./build.sh -r r8p1 -u
    exit 0

    ) || cleanup_and_exit_error

    if test $no_pause = 0
    then
    echo "Hit enter to continue"
    read x
    fi

    echo " "
    echo "make boot script images"  
    ( cd sdcard/boot ; 
    echo "# setenv bootm_boot_mode sec
    setenv bootargs console=tty0 root=/dev/mmcblk0p2 rootwait consoleblank=0 panic=10 drm_kms_helper.drm_leak_fbdev_smem=1
    ext2load mmc 0 0x43000000 sun7i-a20-cubieboard2.dtb
    # Building the initrd is broken. The kernel boots without initrd just fine.
    # ext2load mmc 0 0x44000000 initrd.img-$LINUX_VERSION
    ext2load mmc 0 0x41000000 vmlinuz-$LINUX_VERSION
    # Skip the initrd in the boot command.
    # bootz 0x41000000 0x44000000 0x43000000
    bootz 0x41000000 - 0x43000000" |sudo tee boot.cmd > /dev/null || cleanup_and_exit_error

    echo " "
    echo "Make boot script boot.scr from boot.cmd"
    sudo mkimage -A arm -T script -C none -d boot.cmd boot.scr || cleanup_and_exit_error
    )  || cleanup_and_exit_error

    echo " "
    echo "Add boot script and device tree to the debian installer image"
    if [ -d $BASEDIR/$BUILDDIR/kernel/debian/tmp ]
    then
        sudo cp -v sdcard/boot/boot.cmd sdcard/boot/boot.scr $BUILDDIR/kernel/debian/tmp/boot
        sudo cp -v $BUILDDIR/kernel/arch/arm/boot/dts/sun7i-a20-cubieboard2.dtb $BUILDDIR/kernel/debian/tmp/boot
    else
        sudo cp -v sdcard/boot/boot.cmd sdcard/boot/boot.scr $BUILDDIR/kernel/debian/linux-image/boot
        sudo cp -v $BUILDDIR/kernel/arch/arm/boot/dts/sun7i-a20-cubieboard2.dtb $BUILDDIR/kernel/debian/linux-image/boot
    fi
    
    if test $no_pause = 0
    then
    echo "Hit enter to continue"
    read x
    fi
    
    (
        echo "Re-build the linux image package including MALI"
        cd $BASEDIR/$BUILDDIR/kernel
        if [ -d $BASEDIR/$BUILDDIR/kernel/debian/tmp ]
        then
            dpkg-deb --root-owner-group  --build "debian/tmp" .. || exit 1
        else
            dpkg-deb --root-owner-group  --build "debian/linux-image" .. || exit 1
        fi
    )

    if test $no_pause = 0
    then
    echo "Hit enter to continue"
    read x
    fi

fi # if [ $TARGETARCH = armhf ]


(
  echo "Install kernel and modules and headers"
  
  # uninstall and delete the debug kernel images when they exist
  sudo chroot sdcard bin/bash -c "apt-get remove -y \"linux-image*\""
  sudo chroot sdcard bin/bash -c "apt-get remove -y \"linux-headers*\""
  #sudo chroot sdcard bin/bash -c "apt-get remove -y \"linux-libc-dev*\""
  sudo rm -v sdcard/linux*.deb

  # Clean the boot scripts and device tree. They are now supposed to come with the Debian installer
  sudo rm -vf sdcard/boot/boot.cmd sdcard/boot/boot.scr sdcard/boot/sun7i-a20-cubieboard2.dtb

  
  rm -fv $BUILDDIR/linux-image-$LINUX_VERSION-dbg*.deb
  
  sudo cp -v $BUILDDIR/linux-*$LINUX_VERSION*.deb sdcard
  
  sudo chroot sdcard bin/bash -c "dpkg -i linux-image-$LINUX_VERSION*.deb linux-headers-$LINUX_VERSION*.deb linux-libc-dev_$LINUX_VERSION*.deb" || exit 1
  #sudo chroot sdcard bin/bash -c "dpkg -i linux-headers-$LINUX_VERSION*.deb" || exit 1
  #sudo chroot sdcard bin/bash -c "dpkg -i linux-libc-dev_$LINUX_VERSION*.deb" || exit 1
  
  #sudo rm -f sdcard/linux-*$LINUX_VERSION*.deb
  
) || cleanup_and_exit_error  


if test $no_pause = 0
then
echo "Hit enter to continue"
read x
fi

echo "Build the Debian installer for the Mali R6P2 blob and includes"
sudo rm -rf build/mali-deb/* || cleanup_and_exit_error
mkdir build/mali-deb/DEBIAN || cleanup_and_exit_error
echo "Package: arm-mali-400-fbdev-blob
Version: 6.2
Section: custom
Priority: optional
Architecture: armhf
Essential: no
Installed-Size: 1060
Maintainer: https://github.com/hor63/horOpenVario
Description: MALI R6P2 userspace blob for fbdev device" > build/mali-deb/DEBIAN/control

mkdir build/mali-deb/usr || cleanup_and_exit_error
mkdir build/mali-deb/usr/include || cleanup_and_exit_error
mkdir build/mali-deb/usr/lib || cleanup_and_exit_error
mkdir build/mali-deb/usr/lib/arm-linux-gnueabihf || cleanup_and_exit_error
cp -Rpv src/mali-blobs/include/fbdev/* build/mali-deb/usr/include/ || cleanup_and_exit_error
cp -Rpv src/mali-blobs/r6p2/arm/fbdev/lib* build/mali-deb/usr/lib/arm-linux-gnueabihf/ || cleanup_and_exit_error
find build/mali-deb/usr/ -type d |xargs chmod -v 755 
find build/mali-deb/usr/include -type f |xargs chmod -v 644
find build/mali-deb/usr/lib -type f |xargs chmod -v 755
dpkg-deb --root-owner-group --build build/mali-deb || cleanup_and_exit_error
sudo mv -v build/mali-deb.deb sdcard/mali-deb-R6P2.deb || cleanup_and_exit_error
sudo chroot sdcard bin/bash -c "dpkg -i mali-deb-R6P2.deb" || cleanup_and_exit_error

echo "Build the Debian installer for the Mali R8P1 blob and includes"
sudo rm -rf build/mali-deb/* || cleanup_and_exit_error
mkdir build/mali-deb/DEBIAN || cleanup_and_exit_error
echo "Package: arm-mali-400-fbdev-blob
Version: 8.1
Section: custom
Priority: optional
Architecture: armhf
Essential: no
Installed-Size: 1060
Maintainer: https://github.com/hor63/horOpenVario
Description: MALI R8P1 userspace blob for fbdev device" > build/mali-deb/DEBIAN/control

mkdir build/mali-deb/usr || cleanup_and_exit_error
mkdir build/mali-deb/usr/include || cleanup_and_exit_error
mkdir build/mali-deb/usr/lib || cleanup_and_exit_error
mkdir build/mali-deb/usr/lib/arm-linux-gnueabihf || cleanup_and_exit_error
cp -Rpv src/mali-blobs/include/fbdev/* build/mali-deb/usr/include/ || cleanup_and_exit_error
cp -Rpv src/mali-blobs/r8p1/arm/fbdev/lib* build/mali-deb/usr/lib/arm-linux-gnueabihf/ || cleanup_and_exit_error
find build/mali-deb/usr/ -type d |xargs chmod -v 755 
find build/mali-deb/usr/include -type f |xargs chmod -v 644
find build/mali-deb/usr/lib -type f |xargs chmod -v 755
dpkg-deb --root-owner-group --build build/mali-deb || cleanup_and_exit_error
sudo mv -v build/mali-deb.deb sdcard/mali-deb-R8P1.deb || cleanup_and_exit_error
# sudo chroot sdcard bin/bash -c "dpkg -i mali-deb-R8P1.deb" || cleanup_and_exit_error

if test $no_pause = 0
then
echo "--------------  Almost done --------------------"
echo "Hit enter to continue"
read x
fi

echo "Unmount the SD card image"  
sync
sudo umount sdcard/sys
sudo umount sdcard/proc
sudo umount sdcard/dev/pts
sudo umount sdcard/dev
sudo umount sdcard/boot
sudo umount sdcard
sudo losetup -d /dev/loop5
#exit 0
echo "Copy the SD card image \"sd.img\" to the SD card raw device"  
echo " ----------------- Done -------------------------"
