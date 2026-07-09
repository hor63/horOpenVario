#!/bin/bash

qemu-system-x86_64 -kernel build/kernel/arch/x86/boot/bzImage -append "console=tty0 root=/dev/sda2 rootwait ro" \
	-drive file=sd.img,format=raw,if=ide \
	-vga virtio -display gtk,gl=on \
	-m 2G \
	-device virtio-gpu-gl -initrd initrd.img -smp 2,cores=2 $*

#	-enable-kvm \
#	-vga virtio -display gtk,zoom-to-fit=on,gl=on \
