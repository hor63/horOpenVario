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

# ==========================================
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
} # cleanup_and_exit_error ()

# ===================================================
select_arch_and_distribution () {

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

while test -z "$distris"
do

    echo " "
    echo "Selection of distributions which can be installed."
    echo "Enter:"
    echo "  a - Artful"
    echo "  b - Bionic - LTS"
    echo "  f - Focal  - LTS (default)"
    echo "  x - Xenial - LTS"

    read x

    case y"$x" in
        ya)
            distris="artful"
            ;;
        yb)
            distris="bionic"
            ;;
        yf)
            distris="focal"
            ;;
        yx)
            distris="xenial"
            ;;
        y)
            distris="focal"
            ;;
        *)
            echo "Invalid input \"$x\"."
            echo "Allowed are 'x', 'a', 'b'"
        ;;
    esac

done
} # select_arch_and_distribution ()

# ==========================================
install_build_packages () {
echo ""
echo "Install required packages for building U-Boot, the kernel,"
echo "and the root file system."
if test $NO_PAUSE = 0
then
echo "Hit enter to continue"
read x
fi

sudo apt-get update
sudo apt-get install -y \
    git \
    build-essential \
    crossbuild-essential-armhf \
    bison \
    flex \
    gawk \
    python \
    python3 \
    initramfs-tools \
    command-not-found \
    u-boot-tools \
    dpkg \
    parted \
    debootstrap \
    qemu-user-static \
    bc \
    rsync \
    libssl-dev \
    quilt \
    avahi-daemon avahi-discover libnss-mdns
} # install_build_packages ()


# ==========================================
create_partition_sd_image () {
echo ""
echo "Create and partition the SD image"
if test $NO_PAUSE = 0
then
echo "Hit enter to continue"
read x
fi

rm -f sd.img || exit 1
dd if=/dev/zero of=sd.img bs=1M seek=4096 count=0 || exit 1
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

} # create_partition_sd_image ()

# ==========================================
format_mount_sd_image () {

echo " "  
echo "Format and mount the SD image"  
if test $NO_PAUSE = 0
then
echo "Hit enter to continue"
read x
fi

sudo losetup /dev/loop5 sd.img || exit 1
sudo partprobe /dev/loop5 || cleanup_and_exit_error
sudo mkfs.ext2 -F /dev/loop5p1 || cleanup_and_exit_error
sudo mkfs.ext2 -F /dev/loop5p2 || cleanup_and_exit_error

mkdir -p sdcard

sudo mount /dev/loop5p2 sdcard || cleanup_and_exit_error
sudo mkdir -p sdcard/boot || cleanup_and_exit_error
sudo mount /dev/loop5p1 sdcard/boot || cleanup_and_exit_error

} # format_mount_sd_image ()

# ==========================================
download_base_system_tarball () {

echo " "
echo "Download the base installation as tarball"
if test $NO_PAUSE = 0
then
echo "Hit enter to continue"
read x
fi

DEBOOTSTRAP_CACHE=$BASEDIR/build/ubuntu/debootstrap-${distris}-${TARGETARCH}.tar

echo "DEBOOTSTRAP_CACHE=$DEBOOTSTRAP_CACHE"

if [ -f $DEBOOTSTRAP_CACHE ]
then
if test $NO_PAUSE = 0
then
    echo " "
    echo "The root file system cache $DEBOOTSTRAP_CACHE is already here."
    echo "  Do you want to keep it? [Yn]"
    read x
    if [ "$x" == "n" -o "$x" == "N" ]
    then
        sudo rm $DEBOOTSTRAP_CACHE
    fi
    fi
fi

if [ ! -f $DEBOOTSTRAP_CACHE ]
then
    echo " "
    echo "Download base packages for $distris distribution and store them in $DEBOOTSTRAP_CACHE"
    sudo rm -rf tmp/*
    sudo debootstrap --verbose --arch=$TARGETARCH --make-tarball=$DEBOOTSTRAP_CACHE $distris tmp || cleanup_and_exit_error
fi

} # download_base_system_tarball ()

# ==========================================
install_base_system () {

# Copy the static emulator image to the SD card to be able to run programs in the target architecture
if [ -f /usr/bin/$EMULATOR ]
then
    sudo mkdir -p sdcard/usr/bin || cleanup_and_exit_error
    sudo cp -v /usr/bin/$EMULATOR sdcard/usr/bin || cleanup_and_exit_error
fi

echo " "
echo "Create the root file system for $distris distribution with:"
echo "\"sudo debootstrap --verbose --arch=$TARGETARCH --unpack-tarball=$DEBOOTSTRAP_CACHE $distris sdcard \""
if test $NO_PAUSE = 0
then
echo "Hit enter to continue"
read x
fi
sudo debootstrap --verbose --arch=$TARGETARCH --unpack-tarball=$DEBOOTSTRAP_CACHE $distris sdcard || cleanup_and_exit_error

} # install_base_system ()

# ==========================================
update_complete_base_system () {

# Mount the dynamic kernel managed file systems for a pleasant CHROOT experience
sudo mount -t sysfs sysfs sdcard/sys
sudo mount -t proc proc sdcard/proc
sudo mount -t devtmpfs udev sdcard/dev
sudo mount -t devpts devpts sdcard/dev/pts

echo " "
echo "Please enter the new root password of the target image"
sudo chroot sdcard /bin/bash -c "passwd root"

echo " "
echo "Do you want to use a local APT-Proxy? [y|N]"
echo "  To use this feature you must have apt-proxy-ng installed."
read x
if [ y$x = yy -o y$x = yY ]
then
    APT_PROXY_HOST=localhost
    APT_PROXY_PORT=3142

    echo "Enter the proxy host [localhost]"
    read x
    if [ y$x != y ]
    then
        APT_PROXY_HOST="$x"
    fi

    echo "Enter the proxy port [3142]"
    read x
    if [ y$x != y ]
    then
        APT_PROXY_PORT="$x"
    fi

    echo "Acquire::http::Proxy \"http://$APT_PROXY_HOST:$APT_PROXY_PORT\";
Acquire::https::Proxy \"http://$APT_PROXY_HOST:$APT_PROXY_PORT\";" | sudo tee sdcard/etc/apt/apt.conf.d/00aptproxy
fi


echo " "
echo "Update the repository sources"
if test $NO_PAUSE = 0
then
echo "Hit enter to continue"
read x
fi
# Read the server name from the initial sources.list.
if [ ! -f sdcard/etc/apt/sources.list.bak ]
then
    sudo mv sdcard/etc/apt/sources.list sdcard/etc/apt/sources.list.bak || cleanup_and_exit_error
    (
        cat sdcard/etc/apt/sources.list.bak | while read deb debserver distr package 
        do
            for i in main restricted universe multiverse
            do
                echo "deb $debserver $distr $i" 
                for k in updates backports security
                do
                    echo "deb $debserver $distr-$k $i"  
                done
            done
        done
    ) | sudo tee sdcard/etc/apt/sources.list || cleanup_and_exit_error
fi

echo " "
echo "Update the installation"
if test $NO_PAUSE = 0
then
echo "Hit enter to continue"
read x
fi

sudo chroot sdcard /bin/bash -c "apt-get -y update"
sudo chroot sdcard /bin/bash -c "apt-get -y dist-upgrade"

if test $NO_PAUSE = 0
then
echo "Hit enter to continue"
read x
fi

echo " "
echo "Write /etc/fstab"
echo "# /etc/fstab: static file system information.
#
# Use 'blkid' to print the universally unique identifier for a
# device; this may be used with UUID= as a more robust way to name devices
# that works even if disks are added and removed. See fstab(5).
#
# <file system> <mount point>   <type>  <options>       <dump>  <pass>
/dev/mmcblk0p2       /               ext2    nodiratime,errors=remount-ro 0       1
/dev/mmcblk0p1       /boot           ext2    nodiratime 0       1
" | sudo tee sdcard/etc/fstab 

echo " "
echo "Please enter the host name of the target computer"
read x
sudo chroot sdcard /bin/bash -c "hostname $x"
echo "hostname is now:"
sudo chroot sdcard /bin/bash -c "hostname"
# Make the hostname permanent in the hostname file.
# By default it is set to the name of the build machine.
echo $x |sudo tee sdcard/etc/hostname >/dev/null

echo " "
echo "Install initramfs tools"
echo "Install bash suggestions of packages to install for missing commands"
echo "Install bash completion"
echo "Install U-Boot tools"
echo "Install zeroconfig components and parted"
echo "Install net-tools nfs and ssh server"
if test $NO_PAUSE = 0
then
echo "Hit enter to continue"
read x
fi
sudo chroot sdcard /bin/bash -c "apt-get -y install initramfs-tools command-not-found bash-completion u-boot-tools \
    avahi-daemon avahi-utils libnss-mdns parted \
    nfs-common \
    net-tools ifupdown \
    openssh-server" || cleanup_and_exit_error

} # update_complete_base_system ()

# ==========================================
install_network_management () {

echo " "
echo "Do you want to configure network adapters, WiFi... manually"
echo "  or menu based with nmtui (network manager text UI) or wicd?"
echo "Please enter n(mtui) , m(anual) or w(icd). Default 'n'"
read x

if [ y$x = "y" ]
then
    x=n
fi

if [ y$x = "yw" ]
then
    sudo chroot sdcard /bin/bash -c "apt-get -y install wicd-cli wicd-curses wicd-daemon" || cleanup_and_exit_error

    if test $NO_PAUSE = 0
    then
        echo "Hit enter to continue"
        read x
    fi
fi

if [ y$x = "yn" ]
then
    sudo chroot sdcard /bin/bash -c "apt-get -y install network-manager" || echo "Please run \"apt-get reinstall network-manager\" after booting the target device."
    echo "Please run \"nmtui\" to configure the network after booting the target device"
    if test $NO_PAUSE = 0
    then
        echo "Hit enter to continue"
        read x
    fi
fi

# Allow network connection by USB tethering (e.g. an Android phone) to come up automatically
# Allow the built-in Ethernet interface to come up automatically
# Do not start them at boot time. When Ethernet is not connected system startup is stuck
# for agonizing 5 minutes. Let udev hotplug handle the startup.
echo "# auto usb0
allow-hotplug usb0
iface usb0 inet dhcp
iface usb0 inet6 auto

# auto eth0
allow-hotplug eth0
iface eth0 inet dhcp
iface eth0 inet6 auto" | sudo tee -a sdcard/etc/network/interfaces

} # install_network_management ()

# ==========================================
rebuild_u_boot () {

if test $NO_PAUSE = 0
then
echo "Hit enter to continue"
read x
fi
echo " "
echo "Rebuild uboot"

( 
  $BUILDDIR/u-boot/build.sh -j8 || exit 1
) || cleanup_and_exit_error  

} # rebuild_u_boot ()


# ==========================================
build_kernel_deb () {
( 
  echo " "
  echo "Rebuild the kernel"
  if test $NO_PAUSE = 0
  then
  echo "Hit enter to continue"
  read x
  fi

  # Make sure that there is no stale modules directory left.
  # I will derive the linux version from the modules directory name
  rm -rf $BUILDDIR/kernel/debian/*
  
  echo " "
  echo "Delete previous build artifacts"
  rm $BUILDDIR/* 2>/dev/null
  
  if [ $TARGETARCH = armhf ]
  then
    echo " "
    echo "Build the device tree image"
    $BUILDDIR/kernel/build.sh dtbs || exit 1
  fi # if [ $TARGETARCH = armhf ]

  echo " "
  echo "Build Debian kernel package"
  $BUILDDIR/kernel/build.sh -j8 bindeb-pkg || exit 1
  
) || cleanup_and_exit_error  

if [ -d build/kernel/debian/tmp/lib/modules ]
then
LINUX_VERSION=`basename $BUILDDIR/kernel/debian/tmp/lib/modules/*`
else
LINUX_VERSION=`basename $BUILDDIR/kernel/debian/linux-image/lib/modules/*`
fi
echo " "
echo "LINUX_VERSION = $LINUX_VERSION"

} # build_kernel_deb ()



# ==========================================
blacklist_module () {

    local MODULE_NAME=$1

    echo " "
    echo "Blacklist the ${MODULE_NAME} module"
    if test $NO_PAUSE = 0
    then
      echo "Hit enter to continue"
      read x
    fi

    echo "blacklist ${MODULE_NAME}" | sudo tee sdcard/etc/modprobe.d/blacklist-${MODULE_NAME}.conf
    
} # blacklist_module



# ==========================================
load_module () {

    local MODULE_NAME=$1

    echo " "
    echo "Load the ${MODULE_NAME} module upon boot time"
    if test $NO_PAUSE = 0
    then
      echo "Hit enter to continue"
      read x
    fi

    echo "${MODULE_NAME}" | sudo tee -a sdcard/etc/modules

} # load_module



# ==========================================
build_mali_module () {

if [ $TARGETARCH = armhf ]
then

    ( 
    echo " "
    echo "Build the Mali kernel module"
    if test $NO_PAUSE = 0
    then
      echo "Hit enter to continue"
      read x
    fi
    cd src/sunxi-mali
    
    # Clean the structure and prepare for a new build in case of a previous failure
    CROSS_COMPILE=arm-linux-gnueabihf- KDIR=$BASEDIR/$BUILDDIR/kernel ./build.sh -r r8p1 -c >/dev/null 2>&1

    CROSS_COMPILE=arm-linux-gnueabihf- KDIR=$BASEDIR/$BUILDDIR/kernel ./build.sh -r r8p1 -b || exit 1

    ) || cleanup_and_exit_error


    ( 
    echo " "
    echo "Install the Mali kernel module in the kernel DEB image"
    if test $NO_PAUSE = 0
    then
    echo "Hit enter to continue"
    read x
    fi
    cd src/sunxi-mali
    
    #sudo CROSS_COMPILE=arm-linux-gnueabihf- KDIR=$BASEDIR/$BUILDDIR/kernel INSTALL_MOD_PATH=$BASEDIR/sdcard ./build.sh -r r6p2 -i || cleanup_and_exit_error
        if [ -d $BASEDIR/$BUILDDIR/kernel/debian/tmp ]
        then
            CROSS_COMPILE=arm-linux-gnueabihf- KDIR=$BASEDIR/$BUILDDIR/kernel INSTALL_MOD_PATH=$BASEDIR/$BUILDDIR/kernel/debian/tmp ./build.sh -r r8p1 -i || exit 1
        else
            CROSS_COMPILE=arm-linux-gnueabihf- KDIR=$BASEDIR/$BUILDDIR/kernel INSTALL_MOD_PATH=$BASEDIR/$BUILDDIR/kernel/debian/linux-image ./build.sh -r r8p1 -i || exit 1
        fi

    # undo the patches. Otherwise the next build will fail because applying the patches is part of the build option of build.sh
    CROSS_COMPILE=arm-linux-gnueabihf- KDIR=$BASEDIR/$BUILDDIR/kernel ./build.sh -r r8p1 -c
    exit 0

    ) || cleanup_and_exit_error

fi # if [ $TARGETARCH = armhf ]

} # build_mali_module ()

# ==========================================
make_u_boot_script () {

echo " "
echo "make U-Boot boot script"  
if test $NO_PAUSE = 0
then
echo "Hit enter to continue"
read x
fi

( cd sdcard/boot ; 
echo "# setenv bootm_boot_mode sec
setenv bootargs console=tty0 root=/dev/mmcblk0p2 rootwait consoleblank=0 panic=10 drm_kms_helper.drm_leak_fbdev_smem=1
ext2load mmc 0 0x43000000 sun7i-a20-cubieboard2.dtb
# Building the initrd is broken. The kernel boots without initrd just fine.
# ext2load mmc 0 0x44000000 initrd.img-$LINUX_VERSION
ext2load mmc 0 0x41000000 vmlinuz-$LINUX_VERSION
# Skip the initrd in the boot command.
# bootz 0x41000000 0x44000000 0x43000000
bootz 0x41000000 - 0x43000000" |sudo tee boot.cmd || cleanup_and_exit_error

echo " "
echo "Make boot script boot.scr from boot.cmd"
if test $NO_PAUSE = 0
then
echo "Hit enter to continue"
read x
fi
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

} # make_u_boot_script ()

# ==========================================
update_kernel_deb_package () {

if test $NO_PAUSE = 0
then
echo "Hit enter to continue"
read x
fi


(
    echo " "
    echo "Re-build the linux image package including MALI and boot script"
    cd $BASEDIR/$BUILDDIR/kernel
    if [ -d $BASEDIR/$BUILDDIR/kernel/debian/tmp ]
    then
        dpkg-deb --root-owner-group  --build "debian/tmp" .. || exit 1
    else
        dpkg-deb --root-owner-group  --build "debian/linux-image" .. || exit 1
    fi
)

} # update_kernel_deb_package ()

# ==========================================
install_kernel_deb () {

echo " "
echo "Install kernel and modules and headers"
if test $NO_PAUSE = 0
then
echo "Hit enter to continue"
read x
fi

(

# delete the debug kernel images when they exist
rm -fv $BUILDDIR/linux-image-$LINUX_VERSION-dbg*.deb

# Clean the boot scripts and device tree. They are now supposed to come with the Debian installer
sudo rm -vf sdcard/boot/boot.cmd sdcard/boot/boot.scr sdcard/boot/sun7i-a20-cubieboard2.dtb

sudo cp -v $BUILDDIR/linux-*$LINUX_VERSION*.deb sdcard

sudo chroot sdcard bin/bash -c "dpkg -i linux-image-$LINUX_VERSION*.deb linux-headers-$LINUX_VERSION*.deb linux-libc-dev_$LINUX_VERSION*.deb" || exit 1

) || cleanup_and_exit_error  

# Assign group "video" to the mali device node.
sudo cp -v setup-ubuntu/etc/udev/rules.d/50-mali.rules sdcard/etc/udev/rules.d/

} # install_kernel_deb ()

# ==========================================
install_linux_firmware () {

echo " "
echo "Install Linux firmware"
if test $NO_PAUSE = 0
then
echo "Hit enter to continue"
read x
fi

sudo chroot sdcard /bin/bash -c "apt-get -y install linux-firmware" || cleanup_and_exit_error

} # install_linux_firmware ()

# ==========================================
copy_installation_support () {

echo "Copy Ubuntu installation instructions and support files to /usr/share/doc/horOpenVario on the target" 
if test $NO_PAUSE = 0
then
echo "Hit enter to continue"
read x
fi
sudo mkdir -p sdcard/usr/share/doc/horOpenVario
sudo cp -Rv --preserve=mode,timestamps setup-ubuntu/* sdcard/usr/share/doc/horOpenVario || cleanup_and_exit_error
# sudo tar -czf sdcard/boot/setup-ubuntu.tgz setup-ubuntu/ || cleanup_and_exit_error

#echo "Copy boot environment ot SD card image"  
#sudo cp -v build/boot/* sdcard/boot || cleanup_and_exit_error

} # copy_installation_support ()

# ==========================================
install_u_boot () {

if [ $TARGETARCH = armhf ]
then

echo " "
echo "Copy U-Boot to the SD image"
if test $NO_PAUSE = 0
then
echo "Hit enter to continue"
read x
fi
sudo dd if=$BUILDDIR/u-boot/u-boot-sunxi-with-spl.bin of=/dev/loop5 bs=1024 seek=8 || cleanup_and_exit_error

fi # if [ $TARGETARCH = armhf ]

} # install_u_boot ()

# ==========================================
install_dev_packages () {

# write the list of required packages for development and compiling openEVario and XCSoar
# into a text file for immediate or later installation.
echo " build-essential
    g++
    make flex bison
    librsvg2-bin librsvg2-dev
    xsltproc
    imagemagick
    gettext
    ffmpeg
    git quilt zip m4
    automake autoconf autoconf-archive
    ttf-bitstream-vera
    fakeroot
    zlib1g-dev
    libsodium-dev
    libfreetype6-dev
    libpng-dev libjpeg-dev
    libtiff5-dev libgeotiff-dev
    libcurl4-openssl-dev
    libc-ares-dev
    liblua5.2-dev lua5.2
    libxml-parser-perl
    libasound2-dev alsa-base alsaplayer-text alsa-tools alsa-utils
    librsvg2-bin xsltproc
    libinput-dev
    fonts-dejavu" | sudo tee sdcard/dev-packages.txt > /dev/null

echo " mesa-common-dev libgles2-mesa-dev libgl1-mesa-dev \
    libegl1-mesa-dev libgbm-dev" | sudo tee sdcard/mesa-dev-packages.txt > /dev/null
    
echo " "
echo "Do you want to install the XCSoar build components on your computer,"
echo "and on the target image? [Y|n]"
echo "  You can use the installed components on the image also for"
echo "  cross-compiling XCSoar for the Cubieboard2"
read x
if [ y$x = yy -o y$x = yY -o y$x = y ]
then
  sudo chroot sdcard /bin/bash -c "cat /dev-packages.txt |xargs apt-get -y install " || cleanup_and_exit_error

  cat sdcard/dev-packages.txt | xargs sudo apt-get -y install || cleanup_and_exit_error
  
  if test $WITH_MALI = 0
  then
    sudo chroot sdcard /bin/bash -c "cat /mesa-dev-packages.txt |xargs apt-get -y install " || cleanup_and_exit_error
  fi

# Mesa is incompatible with Mali on the target device.
# Cross tools are useless on the target machine.
  cat sdcard/mesa-dev-packages.txt | \
    xargs sudo apt-get -y install crossbuild-essential-armhf || cleanup_and_exit_error
    
fi # Do you want to install the XCSoar build components?

} # install_dev_packages ()

# ==========================================
config_locale_keyboard () {

echo " "
echo "Configure locales and time zone and keyboard"
if test $NO_PAUSE = 0
then
echo "Hit enter to continue"
read x
fi
sudo chroot sdcard /bin/bash -c "apt-get -y update"
sudo chroot sdcard /bin/bash -c "apt-get -y dist-upgrade"
sudo chroot sdcard /bin/bash -c "apt-get -y install locales keyboard-configuration console-setup"
sudo chroot sdcard /bin/bash -c "dpkg-reconfigure tzdata"
sudo chroot sdcard /bin/bash -c "dpkg-reconfigure locales"
sudo chroot sdcard /bin/bash -c "dpkg-reconfigure keyboard-configuration"
sudo chroot sdcard /bin/bash -c "apt-get -y update"
sudo chroot sdcard /bin/bash -c "apt-get -y dist-upgrade"

} # config_locale_keyboard ()

# ==========================================
build_mali_blob_deb () {

local MALI_VERSION=$1
local MALI_PATCH=$2
local INSTALL_MALI_BLOB=$3

echo " "
echo "Build the Debian installer for the Mali R${MALI_VERSION}P${MALI_PATCH} blob and includes"
if test $NO_PAUSE = 0
then
echo "Hit enter to continue"
read x
fi

sudo rm -rf build/mali-deb/* || cleanup_and_exit_error
mkdir -p build/mali-deb/DEBIAN || cleanup_and_exit_error
echo "Package: arm-mali-400-fbdev-blob
Version: $MALI_VERSION.$MALI_PATCH
Section: custom
Priority: optional
Architecture: armhf
Essential: no
Installed-Size: 1060
Maintainer: https://github.com/hor63/horOpenVario
Description: MALI R${MALI_VERSION}P${MALI_PATCH} userspace blob for fbdev device" > build/mali-deb/DEBIAN/control

mkdir build/mali-deb/usr || cleanup_and_exit_error
mkdir build/mali-deb/usr/include || cleanup_and_exit_error
mkdir build/mali-deb/usr/lib || cleanup_and_exit_error
mkdir build/mali-deb/usr/lib/arm-linux-gnueabihf || cleanup_and_exit_error
cp -Rpv src/mali-blobs/include/fbdev/* build/mali-deb/usr/include/ || cleanup_and_exit_error
cp -Rpv src/mali-blobs/r${MALI_VERSION}p${MALI_PATCH}/arm/fbdev/lib* build/mali-deb/usr/lib/arm-linux-gnueabihf/ || cleanup_and_exit_error
find build/mali-deb/usr/ -type d |xargs chmod -v 755 
find build/mali-deb/usr/include -type f |xargs chmod -v 644
find build/mali-deb/usr/lib -type f |xargs chmod -v 755
dpkg-deb --root-owner-group --build build/mali-deb || cleanup_and_exit_error
sudo mv -v build/mali-deb.deb sdcard/mali-deb-R${MALI_VERSION}P${MALI_PATCH}.deb || cleanup_and_exit_error

if [ "y$INSTALL_MALI_BLOB" = yy ]
then
  echo " "
  echo "Install the Mali R${MALI_VERSION}P${MALI_PATCH} blob and includes"
  if test $NO_PAUSE = 0
  then
  echo "Hit enter to continue"
  read x
  fi
  sudo chroot sdcard bin/bash -c "dpkg -i mali-deb-R${MALI_VERSION}P${MALI_PATCH}.deb" || cleanup_and_exit_error
  
  # load the MALI module at boot time.
  echo mali | sudo tee -a sdcard/etc/modules > /dev/null

fi # if [ "y$INSTALL_MALI_BLOB" = yy ]  

} # build_mali_blob_deb ()

# ==========================================
finish_installation () {

echo " "
echo "Install man pages"
if test $NO_PAUSE = 0
then
echo "Hit enter to continue"
read x
fi

sudo chroot sdcard /bin/bash -c "apt-get -y install man-db"

echo " "
echo "Update the installation finally"
if test $NO_PAUSE = 0
then
echo "Hit enter to continue"
read x
fi
sudo chroot sdcard /bin/bash -c "apt-get -y update"
sudo chroot sdcard /bin/bash -c "apt-get -y dist-upgrade"

if test $NO_PAUSE = 0
then
echo " "
echo "--------------  Almost done --------------------"
echo "Hit enter to continue"
read x
fi

echo " "
echo "Unmount the SD card image"  
sync
sudo umount sdcard/sys
sudo umount sdcard/proc
sudo umount sdcard/dev/pts
sudo umount sdcard/dev
sudo umount sdcard/boot
sudo umount sdcard
sudo losetup -d /dev/loop5

} # finish_installation ()

# ==========================================
# == Start of the main program =============
# ==========================================

NO_PAUSE=0
if test x"$1" = "x--no-pause" || test x"$2" = "x--no-pause"
then
	NO_PAUSE=1
fi

WITH_MALI=1
if test x"$1" = "x--no-mali" || test x"$2" = "x--no-mali"
then
	WITH_MALI=0
fi

BASEDIR=`dirname $0`
BASEDIR="`(cd \"$BASEDIR\" ; BASEDIR=\`pwd\`; echo \"$BASEDIR\")`"


echo " "
echo "BASEDIR = $BASEDIR"
export BASEDIR
cd $BASEDIR

echo "Selected distribution is $distris"
echo " "

select_arch_and_distribution
install_build_packages
create_partition_sd_image
format_mount_sd_image
download_base_system_tarball
install_base_system
update_complete_base_system
install_network_management
rebuild_u_boot
build_kernel_deb
build_mali_module
make_u_boot_script
update_kernel_deb_package
install_kernel_deb
install_linux_firmware
copy_installation_support
install_u_boot
install_dev_packages
config_locale_keyboard
load_module sun4i-codec
build_mali_blob_deb 6 2
if $WITH_MALI = 1
then
    # build AND install the blob, and headers.
    build_mali_blob_deb 8 1 y
    # Prevent the lima module from colliding with mali
    blacklist_module lima
    load_module mali
else
    build_mali_blob_deb 8 1
    # Prevent the mali module from colliding with lima
    blacklist_module mali
    load_module lima
fi
finish_installation

echo "Copy the SD card image \"sd.img\" to the SD card raw device"  
echo " ----------------- Done -------------------------"
