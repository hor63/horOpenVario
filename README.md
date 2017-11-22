*This file is part of horOpenVario*

*Copyright (C) 2017  Kai Horstmann <horstmannkai@hotmail.com>*

# Open Vario on Cubieboard 2 running Ubuntu
## horOpenVario

This repository is the main repository of [horOpenVario](https://github.com/hor63/horOpenVario.git).

This build system builds a Linux kernel for a *Cubiebaord 2* with an Allwinner A20 (sun7i) SOC.

The system creates a SD card image which permits installing an Ubuntu Core system on the same SD card.

This repository requires a number of git submodules.
Therefore check it out either with
```
  git clone https://github.com/hor63/horOpenVario.git --recursive
```
or initialize and load the sub-modules separately.
```
  git clone https://github.com/hor63/horOpenVario.git
  cd horOpenVario
  git submodule init
  git submodule update
```


## Build
To perform a complete build run `./makenewimage.sh`. Decide which Ubuntu version you want to install.
Wait.
Then copy the newly created `sd.img` file onto the SD card e.g. with 
```
dd if=sd.img of=/dev/mmcblk0 BS=1M
```
Note that the device name of the SD card can vary. Best is to run `tail -f /var/log/syslog` in one command window while you insert the SD card.
On some system SD cards can be listed as SCSI disk, e.g. /dev/sdc. Take great care to copy the SD card image with `dd` into the correct device.
I once overwrote accidnenty the USB drive from which I run my build Linux system! :D

To install Ubuntu on the target Cubieboard 2 simply insert the SD card into the Cubieboard, connect USB keyboard and a HDMI monitor or TV.
Power it up. Follow the installation instructions on the screen.

