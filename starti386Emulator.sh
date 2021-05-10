#!/bin/bash

# qemu-system-i386 -machine accel=kvm -m 512 -drive index=0,file=sd.img,if=ide,format=raw,media=disk -kernel ./vmlinuz-4.17.3+ -initrd ./initrd.img-4.17.3+  -append "root=/dev/sda2 console=ttyS0" -nographic
qemu-system-i386 -machine accel=kvm -m 512 -drive index=0,file=sd.img,if=ide,format=raw,media=disk -kernel ./vmlinuz-4.17.3+ -initrd ./initrd.img-4.17.3+ -append "root=/dev/sda2"
