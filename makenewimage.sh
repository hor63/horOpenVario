#!/bin/bash

#    This file is part of horOpenVario 
#    Copyright (C) 2017  Kai Horstmann <horstmannkai@hotmail.com>
#


# set -x

no_pause=0
if test x"$1" = "x--no-pause"
then
	no_pause=1
fi


while test -z "$distris"
do

    echo " "
    echo "Selection of distributions which can be installed."
    echo "Enter:"
    echo "  a - Artful"
    echo "  x - Xenial - LTS (default)"

    read x

    case y"$x" in
        ya)
            distris="artful"
            ;;
        yx)
            distris="xenial"
            ;;
        y)
            distris="xenial"
            ;;
        *)
            echo "Invalid input \"$x\"."
            echo "Allowed are 'x', 'a', 'xa', or 'ax'"
        ;;
    esac

done
    
echo "Selected distribution(s) is/are $distris"


( 
  echo "rebuild uboot"
  build/u-boot/build.sh  || exit 1
) || exit 1  

if test $no_pause = 0
then
echo "Hit enter to continue"
read x
fi


( 
  echo "rebuild the kernel"
  build/kernel/build.sh zImage modules dtbs || exit 1
  echo "Copy the kernel and dtb"
  cp -v build/kernel/arch/arm/boot/zImage build/kernel/arch/arm/boot/dts/sun7i-a20-cubieboard2.dtb build/boot
) || exit 1  

if test $no_pause = 0
then
echo "Hit enter to continue"
read x
fi

(
  echo "Install modules"
  rm -rf build/root/lib/modules/*
  build/kernel/build.sh INSTALL_MOD_PATH=../../build/root modules_install || exit 1
) || exit 1  



if test $no_pause = 0
then
echo "Hit enter to continue"
read x
fi

for distri in $distris
do

    initrd=initrd$distri

    (cd build/ubuntu/
    echo "Fetch the Ubuntu net installer initrd"
    if [ -f $initrd.gz ]
    then
    if test $no_pause = 0
    then
        echo "Installer $initrd.gz is already here. Do you want to download again? [yN]"
        read x
        if [ "$x" == "Y" -o "$x" == "y" ]
        then
            rm $initrd.gz
        fi
        fi
    fi

    if [ -f $initrd.gz ]
    then
        echo "$initrd.gz is retained"
    else
        rm -f initrd.gz
        echo "Download $initrd.gz"
        wget "http://ports.ubuntu.com/ubuntu-ports/dists/$distri/main/installer-armhf/current/images/generic/netboot/initrd.gz" || exit 1
        mv initrd.gz $initrd.gz
    fi
    ) || exit 1

    if test $no_pause = 0
    then
    echo "Hit enter to continue"
    read x
    fi

    (cd build/ubuntu/
    echo "Unpack the Ubuntu net installer $initrd.gz"
    sudo rm -rf $initrd.dir
    mkdir $initrd.dir
    cd $initrd.dir
    gunzip < ../$initrd.gz |sudo cpio -idmu || exit 1
    ) || exit 1

    if test $no_pause = 0
    then
    echo "Hit enter to continue"
    read x
    fi

    echo "Copy latest linux-firmare into initrd"
    sudo cp -Rf src/linux-firmware/rtlwifi build/ubuntu/$initrd.dir/lib/firmware
    sudo rm -rf build/ubuntu/$initrd.dir/lib/firmware/4.*

    (cd build/ubuntu/$initrd.dir/lib/modules
    echo "copy the modules into the $initrd.dir tree"
    sudo rm -rf 3.4.*
    sudo cp -Rf ../../../../../build/root/lib/modules/* . || exit 1
    cd ../..
    echo "re-build the initrds"
    find * |cpio -o -H newc |gzip > ../my$initrd.gz || exit 1
    find dev lib/modules |cpio -o -H newc |gzip > ../$initrd.noinst.gz || exit 1
    cd ..
    mkimage -A arm -T ramdisk -C gzip -d my$initrd.gz uMy$initrd || exit 1
    mkimage -A arm -T ramdisk -C gzip -d $initrd.noinst.gz u${initrd}Noinst || exit 1
    # cp -v uMy$initrd  ../boot || exit 1
    # cp -v u${initrd}Noinst  ../boot || exit 1
    cp -v uMy$initrd  ../boot/uMyinitrd || exit 1
    cp -v u${initrd}Noinst  ../boot/uInitrdNoinst || exit 1
    ) || exit 1

done # for distri in $distris
    
    
if test $no_pause = 0
then
echo "Hit enter to continue"
read x
fi

echo "make boot script images"  
( cd build/boot ; 
  for i in *.cmd
  do
    s=`basename $i .cmd`.scr
    echo "Make boot script $s from $i"
    mkimage -A arm -T script -C none -d $i $s || exit 1
  done  )  || exit 1

if test $no_pause = 0
then
echo "Hit enter to continue"
read x
fi


if test $no_pause = 0
then
echo "Hit enter to continue"
read x
fi

echo "Copy Ubuntu installation instructions and support files to build/boot/setup-ubuntu.tgz" 
tar -czf build/boot/setup-ubuntu.tgz setup-ubuntu/

if test $no_pause = 0
then
echo "Hit enter to continue"
read x
fi

echo "Create and partition the SD image"
dd if=/dev/zero of=sd.img bs=1M count=210 || exit 1
echo "o
n
p
1
2048
+200M
p
w
q" | fdisk sd.img || exit 1

if test $no_pause = 0
then
echo "Hit enter to continue"
read x
fi

echo "Format and mount the SD image"  
sudo losetup /dev/loop0 sd.img || exit 1
sudo partprobe /dev/loop0 || exit 1
sudo mkfs.ext2 -F /dev/loop0p1 || exit 1
sudo mount /dev/loop0p1 sdcard/boot || exit 1
echo "Copy boot environment ot SD card image"  
sudo cp -v build/boot/* sdcard/boot || exit 1
df

if test $no_pause = 0
then
echo "Hit enter to continue"
read x
fi

echo "Copy U-Boot to the SD image"
sudo dd if=build/u-boot/u-boot-sunxi-with-spl.bin of=/dev/loop0 bs=1024 seek=8 || exit 1

echo "Unmount the SD card image"  
sudo umount sdcard/boot
sudo losetup -D
sudo losetup 
echo "Copy the SD card image \"sd.img\" to the SD card raw device"  
# cp -v sd.img /mnt/hgfs/D/Users/kai_horstmann/Downloads/Cubieboard/
echo " ----------------- Done -------------------------"
