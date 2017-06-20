#!/bin/bash

#    This file is part of horOpenVario 
#    Copyright (C) 2017  Kai Horstmann <horstmannkai@hotmail.com>
#


# set -x


( cd src/sunxi-tools
  echo "rebuild fex compiler"
  make bin2fex fex2bin || exit 1
) || exit 1  

echo "Hit enter to continue"
read x


( cd src/uboot-mainline
  echo "rebuild uboot"
  make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf-  || exit 1
) || exit 1  

echo "Hit enter to continue"
read x


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
  # make -i clean
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

(cd build/ubuntu/
 echo "Fetch the Ubuntu net installer initrd"
 if [ -f initrd.gz ]
 then
   echo "Installer is already here. Do you want to download again? [yN]"
   read x
   if [ "$x" == "Y" -o "$x" == "y" ]
   then
     rm initrd.gz
   fi
 fi

 if [ -f initrd.gz ]
 then
   echo "initrd.gz is retained"
 else
   echo "Download initrd.gz"
   wget "http://ports.ubuntu.com/ubuntu-ports/dists/xenial/main/installer-armhf/current/images/generic/netboot/initrd.gz" || exit 1
 fi
) || exit 1

echo "Hit enter to continue"
read x

(cd build/ubuntu/
 echo "Unpack the Ubuntu net installer initrd"
 sudo rm -rf initrd.dir
 mkdir initrd.dir
 cd initrd.dir
 gunzip < ../initrd.gz |sudo cpio -idmu || exit 1
) || exit 1

echo "Hit enter to continue"
read x

(cd build/ubuntu/initrd.dir/lib/modules
 echo "copy the modules into the initrd tree"
 sudo rm -rf 3.4.*
 sudo cp -R ../../../../../build/root/lib/modules/3.4* .
 cd ../..
 echo "re-build the initrds"
 find * |cpio -o -H newc |gzip > ../myinitrd.gz || exit 1
 find dev lib/modules/3.4.* |cpio -o -H newc |gzip > ../initrd.noinst.gz || exit 1
 cd ..
 mkimage -A arm -T ramdisk -C gzip -d myinitrd.gz uMyinitrd || exit 1
 mkimage -A arm -T ramdisk -C gzip -d initrd.noinst.gz uInitrdNoinst || exit 1
 cp -v uMyinitrd  ../boot || exit 1
 cp -v uInitrdNoinst  ../boot || exit 1
) || exit 1

echo "Hit enter to continue"
read x

echo "make boot script images"  
( cd build/boot ; 
  for i in *.cmd
  do
    s=`basename $i .cmd`.scr
    echo "Make boot script $s from $i"
    mkimage -A arm -T script -C none -d $i $s || exit 1
  done  )  || exit 1

echo "Hit enter to continue"
read x

echo "compile FEX files to binary script files"
( 
  cd build/boot ; 
  for i in *.fex
  do
    s=`basename $i .fex`.bin
    echo "Compile fex file $i to binary script $s"
    ../../src/sunxi-tools/fex2bin -v $i $s  || exit 1
  done
) || exit 1


echo "Hit enter to continue"
read x

echo "Copy Ubuntu installation instructions and support files to build/boot/setup-ubuntu.tgz" 
tar -czf build/boot/setup-ubuntu.tgz setup-ubuntu/

echo "Hit enter to continue"
read x
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

echo "Hit enter to continue"
read x
echo "Format and mount the SD image"  
sudo losetup /dev/loop0 sd.img || exit 1
sudo partprobe /dev/loop0 || exit 1
sudo mkfs.ext2 -F /dev/loop0p1 || exit 1
sudo mount /dev/loop0p1 sdcard/boot || exit 1
echo "Copy boot environment ot SD card image"  
sudo cp -v build/boot/* sdcard/boot || exit 1
df

echo "Hit enter to continue"
read x

echo "Copy U-Boot to the SD image"
sudo dd if=src/uboot-mainline/u-boot-sunxi-with-spl.bin of=/dev/loop0 bs=1024 seek=8 || exit 1

echo "Unmount the SD card image"  
sudo umount sdcard/boot
sudo losetup -D
sudo losetup 
echo "Copy the SD card image \"sd.img\" to the SD card raw device"  
# cp -v sd.img /mnt/hgfs/D/Users/kai_horstmann/Downloads/Cubieboard/
echo " ----------------- Done -------------------------"
