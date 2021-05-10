#!/bin/bash

#    This file is part of horOpenVario 
#    Copyright (C) 2017  Kai Horstmann <horstmannkai@hotmail.com>
#


# set -x

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


while test -z "$distris"
do

    echo " "
    echo "Selection of distributions which can be installed."
    echo "Enter:"
    echo "  a - Artful"
    echo "  b - Bionic - LTS (default)"
    echo "  x - Xenial - LTS"

    read x

    case y"$x" in
        ya)
            distris="artful"
            ;;
        yb)
            distris="bionic"
            ;;
        yx)
            distris="xenial"
            ;;
        y)
            distris="bionic"
            ;;
        *)
            echo "Invalid input \"$x\"."
            echo "Allowed are 'x', 'a', 'b'"
        ;;
    esac

done
    
echo "Selected distribution is $distris"

if test $no_pause = 0
then
echo "Hit enter to continue"
read x
fi

echo "Create and partition the SD image"
rm -f sd.img || exit 1
dd if=/dev/zero of=sd.img bs=1M count=3052 || exit 1
echo "o
n
p
1
2048
+200M
n
p
2


p
w
q" | fdisk sd.img || exit 1

if test $no_pause = 0
then
echo "Hit enter to continue"
read x
fi

echo "Format and mount the SD image"  
sudo losetup /dev/loop5 sd.img || exit 1
sudo partprobe /dev/loop5 || exit 1
sudo mkfs.ext2 -F /dev/loop5p1 || exit 1
sudo mkfs.ext2 -F /dev/loop5p2 || exit 1

sudo mount /dev/loop5p2 sdcard || exit 1
sudo mkdir -p sdcard/boot || exit 1
sudo mount /dev/loop5p1 sdcard/boot || exit 1

if test $no_pause = 0
then
echo "Hit enter to continue"
read x
fi

DEBOOTSTRAP_CACHE=$BASEDIR/build/ubuntu/debootstrap-${distris}-${TARGETARCH}.tar

echo "DEBOOTSTRAP_CACHE=$DEBOOTSTRAP_CACHE"

if [ -f $DEBOOTSTRAP_CACHE ]
then
if test $no_pause = 0
then
    echo "Root file system cache $DEBOOTSTRAP_CACHE is already here. Do you want to download again? [yN]"
    read x
    if [ "$x" == "Y" -o "$x" == "y" ]
    then
        sudo rm $DEBOOTSTRAP_CACHE
    fi
    fi
fi

echo "Download base packages for $distris distribution and store them in $DEBOOTSTRAP_CACHE"
if [ ! -f $DEBOOTSTRAP_CACHE ]
then
    echo "debootstrap --verbose --arch=$TARGETARCH --make-tarball=$DEBOOTSTRAP_CACHE $distris tmp"
    sudo debootstrap --verbose --arch=$TARGETARCH --make-tarball=$DEBOOTSTRAP_CACHE $distris tmp || exit 1
fi

# Copy the static emulator image to the SD card to be able to run programs in the target architecture
if [ -f /usr/bin/$EMULATOR ]
then
    sudo mkdir -p sdcard/usr/bin || exit 1
    sudo cp -v /usr/bin/$EMULATOR sdcard/usr/bin || exit 1
fi

echo "Create the root file system for $distris distribution"
echo "sudo debootstrap --verbose --arch=$TARGETARCH --unpack-tarball=$DEBOOTSTRAP_CACHE $distris sdcard"
sudo debootstrap --verbose --arch=$TARGETARCH --unpack-tarball=$DEBOOTSTRAP_CACHE $distris sdcard || exit 1

# Mount the dynamic kernel managed file systems for a pleasant CHROOT experience
sudo mount -t sysfs sysfs sdcard/sys
sudo mount -t proc proc sdcard/proc
sudo mount -t devtmpfs udev sdcard/dev
sudo mount -t devpts devpts sdcard/dev/pts


echo "Set the new root password"
sudo chroot sdcard /bin/bash -c "passwd root"

echo "Install and set locales"
sudo chroot sdcard /bin/bash -c "apt-get install locales"
sudo chroot sdcard /bin/bash -c "dpkg-reconfigure locales"


echo "Update the repository sources"
# Read the server name from the initial sources.list.
if [ ! -f sdcard/etc/apt/sources.list.bak ]
then
    sudo mv sdcard/etc/apt/sources.list sdcard/etc/apt/sources.list.bak || exit 1
    cat sdcard/etc/apt/sources.list.bak | while read deb debserver distr package 
    do
        echo "deb debserver distr package = $deb $debserver $distr $package"
        for i in main restricted universe multiverse
        do
            echo "deb $debserver $distr $i" |sudo tee -a sdcard/etc/apt/sources.list
            for k in updates backports security
            do
            sudo echo "deb $debserver $distr-$k $i" |sudo tee -a sdcard/etc/apt/sources.list > /dev/null
            done
        done
    done
fi

sudo chroot sdcard /bin/bash -c "apt-get update"
sudo chroot sdcard /bin/bash -c "apt-get upgrade"

echo "Install and set keyboard info"
sudo chroot sdcard /bin/bash -c "apt-get -y install console-data"

sudo chroot sdcard /bin/bash -c "dpkg-reconfigure tzdata"

echo "Write /etc/fstab"
echo "# /etc/fstab: static file system information.
#
# Use 'blkid' to print the universally unique identifier for a
# device; this may be used with UUID= as a more robust way to name devices
# that works even if disks are added and removed. See fstab(5).
#
# <file system> <mount point>   <type>  <options>       <dump>  <pass>
/dev/sda2       /               ext2    nodiratime,errors=remount-ro 0       1
/dev/sda1       /boot           ext2    nodiratime 0       1
" | sudo tee sdcard/etc/fstab >/dev/null

echo " "
echo "Please enter the host name of the image"
read x
sudo chroot sdcard /bin/bash -c "hostname $x"
echo "hostname is now:"
sudo chroot sdcard /bin/bash -c "hostname"
echo " "

echo "Do you want to configure network adapters, WiFi... manually or menu based with wicd?"
echo "Please enter m(anual) or w(icd). Default 'w'"
read x

if [ y$x = "y" ]
then
    x=w
fi

if [ y$x = "yw" ]
then
    sudo chroot sdcard /bin/bash -c "apt-get install -y wicd-cli wicd-curses wicd-daemon" || exit 1
fi

if test $no_pause = 0
then
echo "Hit enter to continue"
read x
fi

( 
  echo "rebuild uboot"
  $BUILDDIR/u-boot/build.sh -j8 || exit 1
) || exit 1  

if test $no_pause = 0
then
echo "Hit enter to continue"
read x
fi


( 
  echo "Rebuild the kernel"

  # Make sure that there is no stale modules directory left.
  # I will derive the linux version from the modules directory name
  rm -rf $BUILDDIR/kernel/debian/tmp/lib/modules/*
  
  # delete previous build artifacts
  rm $BUILDDIR/*
  
  if [ $TARGETARCH = armhf ]
  then
    $BUILDDIR/kernel/build.sh dtbs || exit 1
    echo "Copy the dtb"
    sudo cp -v $BUILDDIR/kernel/arch/arm/boot/dts/sun7i-a20-cubieboard2.dtb sdcard/boot
  fi # if [ $TARGETARCH = armhf ]

  echo "Build Debian kernel package"
  $BUILDDIR/kernel/build.sh -j8 bindeb-pkg || exit 1
  
) || exit 1  

LINUX_VERSION=`basename $BUILDDIR/kernel/debian/tmp/lib/modules/*`
echo "LINUX_VERSION = $LINUX_VERSION"

if test $no_pause = 0
then
echo "Hit enter to continue"
read x
fi


(
  echo "Install kernel and modules and headers"
  
  # delete the debug kernel images
  rm -v $BUILDDIR/linux-image-$LINUX_VERSION-dbg*.deb
  
  sudo cp -v $BUILDDIR/linux-*$LINUX_VERSION*.deb sdcard
  
  sudo chroot sdcard bin/bash -c "dpkg -i linux-image-$LINUX_VERSION*.deb" || exit 1
  sudo chroot sdcard bin/bash -c "dpkg -i linux-headers-$LINUX_VERSION*.deb" || exit 1
  sudo chroot sdcard bin/bash -c "dpkg -i linux-libc-dev_$LINUX_VERSION*.deb" || exit 1
  
  sudo rm -f sdcard/linux-*$LINUX_VERSION*.deb
  
) || exit 1  

if [ $TARGETARCH = armhf ]
then

if test $no_pause = 0
then
echo "Hit enter to continue"
read x
fi

( 
  echo "Build the Mali kernel module"
  cd src/sunxi-mali
  sudo CROSS_COMPILE=arm-linux-gnueabihf- KDIR=$BASEDIR/$BUILDDIR/kernel ./build.sh -r r8p1 -b || exit 1

) || exit 1

if test $no_pause = 0
then
echo "Hit enter to continue"
read x
fi

( 
  echo "Install the Mali kernel module"
  cd src/sunxi-mali
  sudo CROSS_COMPILE=arm-linux-gnueabihf- KDIR=$BASEDIR/$BUILDDIR/kernel INSTALL_MOD_PATH=$BASEDIR/sdcard ./build.sh -r r8p1 -i || exit 1

  # Rebuild the initrd image with the Mali module
  sudo chroot sdcard /bin/bash -c "update-initramfs -u"
  
  # undo the patches. Otherwise the next build will fail because applying the patches is part of the build option of build.sh
  sudo CROSS_COMPILE=arm-linux-gnueabihf- KDIR=$BASEDIR/$BUILDDIR/kernel ./build.sh -r r8p1 -u
  exit 0

) || exit 1

fi # if [ $TARGETARCH = armhf ]

if test $no_pause = 0
then
echo "Hit enter to continue"
read x
fi

echo "Install Linux firmware"
sudo chroot sdcard /bin/bash -c "apt-get install linux-firmware" || exit 1

if test $no_pause = 0
then
echo "Hit enter to continue"
read x
fi

if [ $TARGETARCH = armhf ]
then

echo "make boot script images"  
( cd sdcard/boot ; 
  echo "# setenv bootm_boot_mode sec
setenv bootargs console=tty0 root=/dev/mmcblk0p2 rootwait consoleblank=0 panic=10
ext2load mmc 0 0x43000000 sun7i-a20-cubieboard2.dtb
ext2load mmc 0 0x44000000 initrd.img-$LINUX_VERSION
ext2load mmc 0 0x41000000 vmlinuz-$LINUX_VERSION
bootz 0x41000000 0x44000000 0x43000000" |sudo tee boot.cmd > /dev/null || exit 1

  echo "Make boot script boot.scr from boot.cmd"
  sudo mkimage -A arm -T script -C none -d boot.cmd boot.scr || exit 1
  )  || exit 1

if test $no_pause = 0
then
echo "Hit enter to continue"
read x
fi

fi # if [ $TARGETARCH = armhf ]

if test $no_pause = 0
then
echo "Hit enter to continue"
read x
fi

echo "Copy Ubuntu installation instructions and support files to sdcard/boot/setup-ubuntu.tgz" 
sudo tar -czf sdcard/boot/setup-ubuntu.tgz setup-ubuntu/ || exit 1

#echo "Copy boot environment ot SD card image"  
#sudo cp -v build/boot/* sdcard/boot || exit 1
df

if test $no_pause = 0
then
echo "Hit enter to continue"
read x
fi

if [ $TARGETARCH = armhf ]
then

echo "Copy U-Boot to the SD image"
sudo dd if=$BUILDDIR/u-boot/u-boot-sunxi-with-spl.bin of=/dev/loop5 bs=1024 seek=8 || exit 1

fi # if [ $TARGETARCH = armhf ]
#exit 0

echo "Unmount the SD card image"  
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
