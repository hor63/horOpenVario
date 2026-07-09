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


# ==========================================
cleanup_and_exit_error () {

echo "Unmount the SD card image"  
sync
$SUDO umount sdcard/sys
$SUDO umount sdcard/proc
$SUDO umount sdcard/dev/pts
$SUDO umount sdcard/dev
$SUDO umount sdcard/boot
$SUDO umount sdcard
$SUDO losetup -d ${LOOPDEV}

exit 1
} # cleanup_and_exit_error ()

# ===================================================
select_distribution () {

# Architecture of the target system
TARGETARCH=amd64
ARCH=x86_64 
ARCH_PREFIX=
BUILDDIR=build

while test -z "$distris"
do

    echo " "
    echo "Selection of distributions which can be installed."
    echo "Enter:"
    echo "  f - Focal  - LTS"
    echo "  n - Noble  (default)"
    echo " "
    echo " Debian releases:"
    echo "  ds - Debian stable"
    echo "  dt - Debian testing"

    read x

    case y"$x" in
        yf)
            distris="focal"
            ;;
        yn)
            distris="noble"
            ;;
        yds)
            distris="stable"
            ;;
        ydt)
            distris="testing"
            ;;
        y)
            distris="noble"
            ;;
        *)
            echo "Invalid input \"$x\"."
            echo "Allowed are 'x', 'a', 'b'"
        ;;
    esac

    if test $distris = "stable" -o $distris = "testing"
    then
      DEBIAN=1
    else
      DEBIAN=0
    fi
    
done
} # select_distribution ()


# ==========================================
ask_apt_cache () {
echo " "
echo "Do you want to use a local APT-Proxy? [y|N]"
echo "  To use this feature you must have apt-cacher installed."
echo "  \"apt-cacher-ng\" does not work correctly. "
echo "    If you have installed apt-cacher-ng answer 'n'"
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

  fi
} # ask_apt_cache ()

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

$SUDO apt-get $APT_GET_OPT update
$SUDO apt-get $APT_GET_OPT  install \
  `cat build-packages.txt`

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
dd if=/dev/zero of=sd.img bs=1M seek=4095 count=0 || exit 1
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
q" | $SUDO fdisk sd.img || exit 1

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

LOOPDEV=`$SUDO losetup -f`
if test -z "$LOOPDEV"
then 
    echo "No loop device available. Stop."
    exit 1
else
    echo "Using loop device ${LOOPDEV}"
fi
$SUDO losetup ${LOOPDEV} sd.img || exit 1
$SUDO partprobe ${LOOPDEV} || cleanup_and_exit_error
$SUDO mkfs.ext2 -t ext2 -v -F ${LOOPDEV}p1 || cleanup_and_exit_error
$SUDO mkfs.ext4 -t ext4 -v -F ${LOOPDEV}p2 || cleanup_and_exit_error

mkdir -p sdcard

$SUDO mount -v -o defaults,noatime ${LOOPDEV}p2 sdcard || cleanup_and_exit_error
$SUDO mkdir -p sdcard/boot || cleanup_and_exit_error
$SUDO mount -v -o defaults,noatime ${LOOPDEV}p1 sdcard/boot || cleanup_and_exit_error

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
        $SUDO rm $DEBOOTSTRAP_CACHE
    fi
  fi
fi

if [ ! -f $DEBOOTSTRAP_CACHE ]
then
    echo " "
    echo "Download base packages for $distris distribution and store them in $DEBOOTSTRAP_CACHE"
    $SUDO rm -rf tmp/*
    $SUDO debootstrap --verbose --arch=$TARGETARCH --make-tarball=$DEBOOTSTRAP_CACHE $distris tmp || cleanup_and_exit_error
fi

} # download_base_system_tarball ()

# ==========================================
install_base_system () {

echo " "
echo "Create the root file system for $distris distribution with:"
echo "\"$SUDO debootstrap --verbose --arch=$TARGETARCH --unpack-tarball=$DEBOOTSTRAP_CACHE $distris sdcard \""
if test $NO_PAUSE = 0
then
echo "Hit enter to continue"
read x
fi
$SUDO debootstrap --verbose --arch=$TARGETARCH --unpack-tarball=$DEBOOTSTRAP_CACHE $distris sdcard || cleanup_and_exit_error

} # install_base_system ()

# ==========================================
update_base_system () {

# Mount the dynamic kernel managed file systems for a pleasant CHROOT experience
$SUDO mount -v -t sysfs sysfs sdcard/sys
$SUDO mount -v -t proc proc sdcard/proc
$SUDO mount -v -t devtmpfs udev sdcard/dev
$SUDO mount -v -t devpts devpts sdcard/dev/pts


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
    $SUDO mv sdcard/etc/apt/sources.list sdcard/etc/apt/sources.list.bak || cleanup_and_exit_error
    (
      # Debian has a different repository layout than Ubuntu
      if test $distris = "stable" -o $distris = "testing"
      then
        REPOSITORIES="main non-free contrib"
        if test $distris = "stable"
        then
          UPDATE_PKGS="updates backports backports-sloppy"
        else
          # testing
          UPDATE_PKGS="updates backports"
        fi
      else
        REPOSITORIES="main restricted universe multiverse"
        UPDATE_PKGS="updates backports security"
      fi
      cat sdcard/etc/apt/sources.list.bak | while read deb debserver distr package 
      do
          for i in $REPOSITORIES
          do
              echo "deb $debserver $distr $i" 
              for k in $UPDATE_PKGS
              do
                  echo "deb $debserver $distr-$k $i"  
              done
          done
      done
  ) | $SUDO tee sdcard/etc/apt/sources.list || cleanup_and_exit_error
fi

echo " "
echo "Update the installation"
if test $NO_PAUSE = 0
then
echo "Hit enter to continue"
read x
fi

if [ n$APT_PROXY_HOST != n ]
then
      echo "Acquire::http::Proxy \"http://$APT_PROXY_HOST:$APT_PROXY_PORT\";" | $SUDO tee sdcard/etc/apt/apt.conf.d/00aptproxy
fi

LANG=C.UTF-8 LC_ALL=C $SUDO chroot sdcard /bin/bash -c "apt-get -y update"

LANG=C.UTF-8 LC_ALL=C $SUDO chroot sdcard /bin/bash -c "apt-get -y dist-upgrade"

} # update_base_system ()

install_complete_base_system () {

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
/dev/sda2      /               ext2    defaults,noatime,errors=remount-ro 0       1
/dev/sda1       /boot           ext2    defaults,noatime 0       1
" | $SUDO tee sdcard/etc/fstab


echo " "
echo "Install initramfs tools"
echo "Install bash suggestions of packages to install for missing commands"
echo "Install bash completion"
echo "Install U-Boot tools"
echo "Install zeroconfig components parted and fdisk"
echo "Install net-tools nfs and ssh server"
echo "Install sudo"
if test $NO_PAUSE = 0
then
echo "Hit enter to continue"
read x
fi
LANG=C.UTF-8 LC_ALL=C $SUDO chroot sdcard /bin/bash -c "apt-get -y install\
    initramfs-tools u-boot-tools \
    command-not-found bash-completion \
    avahi-daemon avahi-utils libnss-mdns parted fdisk \
    nfs-common \
    net-tools ifupdown \
    openssh-server \
    libssl-dev \
    bluetooth \
    sudo" || cleanup_and_exit_error

    if test "$DEBIAN" = 1
    then
      apt-file update
      update-command-not-found
    fi
    
} # update_complete_base_system ()

# ==========================================
install_network_management () {

if test $NO_PAUSE = 0
then
  echo " "
  echo "Do you want to configure network adapters, WiFi... manually"
  echo "  or menu based with nmtui (network manager text UI)?"
  echo "Please enter 'n'(mtui)  or 'm'(anual). Default 'n'"
  read x

  if [ y$x = "y" ]
  then
      x=n
  fi
else
  x=n
fi

if [ y$x = "yn" ]
then
    LANG=C.UTF-8 LC_ALL=C $SUDO chroot sdcard /bin/bash -c "apt-get -y install network-manager" || \
      echo "Please run \"apt-get reinstall network-manager\" after booting the target device."
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
iface eth0 inet6 auto" | $SUDO tee -a sdcard/etc/network/interfaces

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
  $BUILDDIR/u-boot/build.sh -j4 || exit 1
) || cleanup_and_exit_error  

} # rebuild_u_boot ()


# ==========================================
build_kernel_deb () {

pushd src/meta-openvario/recipes-kernel/linux/linux-mainline  || exit 1
DEVICETREE_CUSTOM_SOURCES=`echo *.dts`
popd
DEVICETREE_CUSTOM_FILES="allwinner/sun7i-a20-cubieboard2.dtb \
    allwinner/openvario-57-lvds-DS2.dtb allwinner/openvario-57-lvds.dtb allwinner/openvario-7-AM070-DS2.dtb \
    allwinner/openvario-7-CH070-DS2.dtb allwinner/openvario-7-CH070.dtb \
    allwinner/openvario-7-PQ070.dtb"
# The default device tree is for HDMI, and does not activate all serial ports.
devicetree_file="sun7i-a20-cubieboard2.dtb"

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
    cp -v src/meta-openvario/recipes-kernel/linux/linux-mainline/*.dts src/kernel/arch/arm/boot/dts/allwinner  || exit 1
    KDEB_COMPRESS=gzip $BUILDDIR/kernel/build.sh $DEVICETREE_CUSTOM_FILES || exit 1
  fi # if [ $TARGETARCH = armhf ]

  echo " "
  echo "Build Debian kernel package"
  KDEB_COMPRESS=gzip DPKG_FLAGS=-d $BUILDDIR/kernel/build.sh -j4 bindeb-pkg || exit 1
  
) || cleanup_and_exit_error  

LINUX_VERSION=`make -f makefilePrintKernelVersion`  || cleanup_and_exit_error

KERNEL_IMAGE_DIR=linux-image-$LINUX_VERSION

echo " "
echo "LINUX_VERSION = $LINUX_VERSION"
if test $NO_PAUSE = 0
then
  echo "Hit enter to continue"
  read x
fi

} # build_kernel_deb ()


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

    echo "${MODULE_NAME}" | $SUDO tee sdcard/etc/modules-load.d/mali.conf

} # load_module

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
setenv bootargs console=tty0 root=/dev/virtioblk0p2 rootwait consoleblank=0 panic=10
#ext2load virtio 0 0x13000000 openvario.dtb
ext2load virtio 0 0x14000000 initrd.img-$LINUX_VERSION
ext2load virtio 0 0x11000000 vmlinuz-$LINUX_VERSION
# Skip the initrd in the boot command.
# bootz 0x41000000 0x44000000 0x43000000
booti 0x11000000" |$SUDO tee boot.cmd || exit 1

echo " "
echo "Make boot script boot.scr from boot.cmd"
if test $NO_PAUSE = 0
then
echo "Hit enter to continue"
read x
fi
$SUDO mkimage -A x86_64 -T script -C none -d boot.cmd boot.scr || cleanup_and_exit_error
)  || cleanup_and_exit_error

echo " "
echo "Add boot script and device tree to the debian installer image"

DEB_DTB_TARGET_DIR="$BASEDIR/$BUILDDIR/kernel/debian/$KERNEL_IMAGE_DIR/boot"

$SUDO cp -v sdcard/boot/boot.cmd sdcard/boot/boot.scr $DEB_DTB_TARGET_DIR || cleanup_and_exit_error
if [ $TARGETARCH = armhf ]
then
  pushd $BUILDDIR/kernel/arch/arm/boot/dts || cleanup_and_exit_error
  $SUDO cp -v $DEVICETREE_CUSTOM_FILES $DEB_DTB_TARGET_DIR || cleanup_and_exit_error
  popd
fi # if [ $TARGETARCH = armhf ]

# Copy the target dtb to the fixed name used in the boot.cmd file
pushd $DEB_DTB_TARGET_DIR || cleanup_and_exit_error
$SUDO ln -s $devicetree_file openvario.dtb || cleanup_and_exit_error
popd

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
    echo "Re-build the linux image package including the boot script"
    cd $BASEDIR/$BUILDDIR/kernel
    if [ -d $BASEDIR/$BUILDDIR/kernel/debian/tmp ]
    then
        dpkg-deb -Zgzip --root-owner-group  --build "debian/tmp" .. || exit 1
    else
        dpkg-deb -Zgzip --root-owner-group  --build "debian/$KERNEL_IMAGE_DIR" .. || exit 1
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
$SUDO rm -vf sdcard/boot/boot.cmd sdcard/boot/boot.scr sdcard/boot/sun7i-a20-cubieboard2.dtb

$SUDO cp -v $BUILDDIR/linux-*$LINUX_VERSION*.deb sdcard

$SUDO chroot sdcard bin/bash -c "dpkg -i linux-image-$LINUX_VERSION*.deb linux-headers-$LINUX_VERSION*.deb linux-libc-dev_$LINUX_VERSION*.deb" || exit 1

) || cleanup_and_exit_error  

} # install_kernel_deb ()

select_display_device_tree() {
    $SUDO cp build/root/select-display-device-tree.sh sdcard
    $SUDO chmod a-x sdcard/select-display-device-tree.sh
    $SUDO chmod u+x sdcard/select-display-device-tree.sh

    $SUDO chroot sdcard /select-display-device-tree.sh

} # select_display_device_tree

# ==========================================
install_linux_firmware () {

echo " "
echo "Install Linux firmware"
if test $NO_PAUSE = 0
then
echo "Hit enter to continue"
read x
fi

if test $DEBIAN = 1
then
  FIRMWARE_PKG="firmware-atheros firmware-bnx2* \
    firmware-brcm80211 firmware-libertas \
    firmware-linux* firmware-misc-nonfree \
    firmware-realtek firmware-ti-connectivity firmware-zd1211"
else
  FIRMWARE_PKG=linux-firmware
fi

LANG=C.UTF-8 LC_ALL=C $SUDO chroot sdcard /bin/bash -c "apt-get -y install $FIRMWARE_PKG" || cleanup_and_exit_error

} # install_linux_firmware ()

# ==========================================
copy_installation_support () {

echo "Copy Ubuntu installation instructions and support files to /usr/share/doc/horOpenVario on the target" 
if test $NO_PAUSE = 0
then
echo "Hit enter to continue"
read x
fi
$SUDO mkdir -p sdcard/usr/share/doc/horOpenVario
$SUDO cp -Rv --preserve=mode,timestamps setup-ubuntu/* sdcard/usr/share/doc/horOpenVario || cleanup_and_exit_error
# $SUDO tar -czf sdcard/boot/setup-ubuntu.tgz setup-ubuntu/ || cleanup_and_exit_error

#echo "Copy boot environment ot SD card image"  
#$SUDO cp -v build/boot/* sdcard/boot || cleanup_and_exit_error

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
fi # 
echo "$SUDO dd if=$BUILDDIR/u-boot/u-boot-sunxi-with-spl.bin of=${LOOPDEV} bs=1024 seek=8"
$SUDO dd if=$BUILDDIR/u-boot/u-boot-sunxi-with-spl.bin of=${LOOPDEV} bs=1024 seek=8 || cleanup_and_exit_error

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
    libasound2-dev alsaplayer-text alsa-tools alsa-utils
    librsvg2-bin xsltproc
    libinput-dev
    fonts-dejavu
    mesa-common-dev libgles2-mesa-dev libgl1-mesa-dev 
    libegl1-mesa-dev libgbm-dev
    libdbus-1-dev
    libfmt-dev
    sox
    libsdl2-dev
    libpango1.0-dev
    cmake
    libwayland-dev
    libwayland-egl-backend-dev
    gdb
    fonts-noto
    libgettextpo-dev" | $SUDO tee sdcard/dev-packages.txt > /dev/null

    if test $distris = "noble" -o $distris = "stable" -o $distris = "testing"
    then
      echo "liblua5.4-dev lua5.4" | $SUDO tee -a sdcard/dev-packages.txt > /dev/null
    fi
    
if test $NO_PAUSE = 0
then
  echo " "
  echo "Do you want to install the XCSoar build components on your computer,"
  echo "and on the target image? [Y|n]"
  echo "  You can use the installed components on the image also for"
  echo "  cross-compiling XCSoar for the Cubieboard2"
  read x
else
  x=yy
fi

if [ y$x = yy -o y$x = yY -o y$x = y ]
then
  LANG=C.UTF-8 LC_ALL=C $SUDO chroot sdcard /bin/bash -c "cat /dev-packages.txt |xargs apt-get -y install" || cleanup_and_exit_error

  cat sdcard/dev-packages.txt | xargs $SUDO apt-get -y install || cleanup_and_exit_error
  
  LANG=C.UTF-8 LC_ALL=C $SUDO chroot sdcard /bin/bash -c "cat /mesa-dev-packages.txt |xargs apt-get -y install" || cleanup_and_exit_error

# Cross tools are useless on the target machine.
    # To enable cross compilation fix the symbolic links to the system libraries in /lib/arm-linux-gnueabihf
    if [ $TARGETARCH = armhf ]
    then
      fix_lib_symlinks
    fi
    
fi # Do you want to install the XCSoar build components?

echo " "
echo "Install man pages"
if test $NO_PAUSE = 0
then
echo "Hit enter to continue"
read x
fi

LANG=C.UTF-8 LC_ALL=C $SUDO chroot sdcard /bin/bash -c "apt-get -y install man-db"

echo " "
echo "Update the installation finally"
if test $NO_PAUSE = 0
then
echo "Hit enter to continue"
read x
fi
LANG=C.UTF-8 LC_ALL=C $SUDO chroot sdcard /bin/bash -c "apt-get -y update"
LANG=C.UTF-8 LC_ALL=C $SUDO chroot sdcard /bin/bash -c "apt-get -y dist-upgrade"

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
LANG=C.UTF-8 LC_ALL=C $SUDO chroot sdcard /bin/bash -c "apt-get -y update"
LANG=C.UTF-8 LC_ALL=C $SUDO chroot sdcard /bin/bash -c "apt-get -y dist-upgrade"
LANG=C.UTF-8 LC_ALL=C $SUDO chroot sdcard /bin/bash -c "apt-get -y install locales keyboard-configuration console-setup"
LANG=C.UTF-8 LC_ALL=C $SUDO chroot sdcard /bin/bash -c "dpkg-reconfigure tzdata"
LANG=C.UTF-8 LC_ALL=C $SUDO chroot sdcard /bin/bash -c "dpkg-reconfigure locales"
$SUDO chroot sdcard /bin/bash -c "dpkg-reconfigure keyboard-configuration"
$SUDO chroot sdcard /bin/bash -c "apt-get -y update"
$SUDO chroot sdcard /bin/bash -c "apt-get -y dist-upgrade"

} # config_locale_keyboard ()

# ==========================================
# Ubuntu and Debian sym-link a lot of shared libraries with an absolute path
# to /lib/... instead of a relative symbolic link in the same directory.
# This prevents gcc with the option --with-sysroot to find the library in the cross-build root file system.

# Therefore fix these symbolic links by replacing them with relative symbolic links.
fix_lib_symlinks () {

SYS_LIB_DIR=`pwd`/sdcard/lib/$ARCH_PREFIX

# Check if the architecture system library directory exists at all.
if test ! -d $SYS_LIB_DIR
then
  echo "--- Warning! Cannot find system library directory $SYS_LIB_DIR"
  echo "    Skipping fixing library symbolic links"
  return 0
fi

echo " "
echo "Fixing system library symbolic links in $SYS_LIB_DIR"

pushd $SYS_LIB_DIR
pwd

for i in *
do
  if test -L $i
  then
    l=`readlink -f $i`
    if test -n "$l"
    then
      f=`basename $l`
      d=`dirname $l`
      if test \( ! -f $l \) -a \( -f $f \)
      then
        echo "Link sdcard/lib/$ARCH_PREFIX/$i to $f"
        $SUDO rm -fv $i
        $SUDO ln -s $f $i
      fi  
    fi
  fi
done

popd
} # fix_lib_symlinks ()

# ==========================================
finish_installation () {

echo " "
echo "--------------  Almost done --------------------"
echo "Hit enter to continue"
read x

echo " "
echo "Please enter the new root password of the target image"
$SUDO chroot sdcard /bin/bash -c "passwd root"


echo " "
echo "Please enter the host name of the target computer"
read x
# Make the hostname permanent in the hostname file.
# By default it is set to the name of the build machine.
echo $x |$SUDO tee sdcard/etc/hostname >/dev/null

echo " "
echo "Unmount the SD card image"  
sync
$SUDO umount sdcard/sys
$SUDO umount sdcard/proc
$SUDO umount sdcard/dev/pts
$SUDO umount sdcard/dev
$SUDO umount sdcard/boot
$SUDO umount sdcard
$SUDO losetup -d ${LOOPDEV}

} # finish_installation ()

# ==========================================
# == Start of the main program =============
# ==========================================


NO_PAUSE=0
if test x"$1" = "x--no-pause" || test x"$2" = "x--no-pause"
then
	NO_PAUSE=1
	APT_GET_OPT="$APT_GET_OPT -y --allow-downgrades"
fi

BASEDIR=`dirname $0`
export BASEDIR="`(cd \"$BASEDIR\" ; BASEDIR=\`pwd\`; echo \"$BASEDIR\")`"

if test $NO_PAUSE = 0
then
  export SUDO="sudo "
else
  echo " "
  echo "Please enter your password for fully automatic execution."
  echo "If you do not enter your password but just Enter"
  echo "you need to enter your password for \"sudo\" when required in between"
  read x
  if [ x$x = x ]
    export SUDO="sudo "
  then
    export SUDO_ASKPASS=$BASEDIR/givepass.sh
    export SUDO="sudo -A "
    export MY_PASSWD=$x
  fi
fi

echo " "
echo "Do you want to install the system into a disk image? [Yn]"
echo "If you say yes the disk image will be ./sd.img"
read x
if [ "x$x" = x ] || [ "x$x" = y ] || [ "x$x" = Y ]
then
  USE_DISK_IMAGE=y
else
  USE_DISK_IMAGE=n
fi

echo " "
echo "BASEDIR = $BASEDIR"
export BASEDIR
cd $BASEDIR

echo "Selected distribution is $distris"
echo " "

select_distribution
ask_apt_cache
install_build_packages
if [ $USE_DISK_IMAGE = y ]
then
  ./umountSDImage.sh
  create_partition_sd_image
  format_mount_sd_image
else
  echo "Re-create subdirectory sdcard."
  ./umountSDImage.sh
  $SUDO rm -rf sdcard
  $SUDO mkdir sdcard
fi
download_base_system_tarball
install_base_system
update_base_system
install_complete_base_system
install_network_management
if [ $USE_DISK_IMAGE = y ]
then
  rebuild_u_boot
fi
build_kernel_deb
if [ $USE_DISK_IMAGE = y ]
then
  make_u_boot_script
fi
update_kernel_deb_package
install_kernel_deb
install_linux_firmware
copy_installation_support
if [ $USE_DISK_IMAGE = y ]
then
  install_u_boot
fi
install_dev_packages
load_module sun4i-codec
load_module lima
config_locale_keyboard
select_display_device_tree
finish_installation

echo "Copy the SD card image \"sd.img\" to the SD card raw device"  
echo " ----------------- Done -------------------------"
