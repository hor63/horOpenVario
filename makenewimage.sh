#!/bin/bash

#    This file is part of horOpenVario 
#    Copyright (C) 2017  Kai Horstmann <horstmannkai@hotmail.com>
#


# set -x

( cd src/kernel
  echo "rebuild the kernel"
  make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- uImage modules || exit 1
  echo "Copy the kernel"
  cp -v arch/arm/boot/uImage ../../build/boot
) || exit 1  

echo "Hit enter to continue"
read x

( cd src/rtl8188C_8192C_usb_linux_v4.0.2_9000.20130911
  echo "Build the RTL 8192CU driver"
  make -i clean
  make || exit 1
) || exit 

echo "Hit enter to continue"
read x

( cd src/kernel
  echo "Install modules"
  rm -rf ../../build/root/lib/modules/*
  make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- INSTALL_MOD_PATH=../../build/root modules_install || exit 1
) || exit 1  

echo "Hit enter to continue"
read x

( cd src/rtl8188C_8192C_usb_linux_v4.0.2_9000.20130911
  echo "Install RTL 8192CU module"
  make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- INSTALL_MOD_PATH=../../build/root modules_install || exit 1
) || exit 1  

echo "Hit enter to continue"
read x

(cd build/ubuntu/initrd.dir/lib/modules
 echo "copy the modules into the initrd tree"
 sudo rm -rf 3.4.*
 sudo cp -R ../../../../../build/root/lib/modules/3.4* .
 cd ../..
 echo "re-build the initrds"
 find * |cpio -o -H newc |gzip > ../myinitrd.gz
 find dev lib/modules/3.4.* |cpio -o -H newc |gzip > ../initrd.noinst.gz
 cd ..
 mkimage -A arm -T ramdisk -C gzip -d myinitrd.gz uMyinitrd
 mkimage -A arm -T ramdisk -C gzip -d initrd.noinst.gz uInitrdNoinst
 cp -v uMyinitrd  ../boot
 cp -v uInitrdNoinst  ../boot
)


echo "make boot script image"  
( cd build/boot ; mkimage -A arm -T script -C none -d boot.cmd boot.scr 
  mkimage -A arm -T script -C none -d boot.noinitrd.cmd boot.noinitrd.scr 
  for i in *.cmd
  do
    s=`basename $i .cmd`.scr
    echo "Make boot script $s from $i"
    mkimage -A arm -T script -C none -d $i $s
  done  )
echo "compile FEX file to script.bin"
( cd build/boot ; ../../src/sunxi-tools/fex2bin -v openvario.fex script.bin )

echo "Format and mount the SD image"  
sudo losetup /dev/loop0 sd.img
sudo partprobe /dev/loop0
sudo mkfs.ext2 -F /dev/loop0p1
sudo mount /dev/loop0p1 sdcard/boot
echo "Copy boot environment ot SD card image"  
sudo cp -v build/boot/* sdcard/boot
df
echo "Unmount the SD card image"  
sudo umount sdcard/boot
sudo losetup -D
sudo losetup 
# echo "Copy the SD card image to the host"  
# cp -v sd.img /mnt/hgfs/D/Users/kai_horstmann/Downloads/Cubieboard/
echo " ----------------- Done -------------------------"

