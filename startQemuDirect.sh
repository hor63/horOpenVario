#!/bin/bash

qemu-system-x86_64 \
	-bios build/u-boot/u-boot.rom \
	-drive file=sd.img,format=raw,if=virtio \
	-m 2G \
	-display gtk,gl=on \
	-device virtio-gpu-gl,hostmem=1G \
	-smp 4,cores=4 $*

#	-kernel build/kernel/arch/x86/boot/bzImage -append "console=tty0 root=/dev/sda2 ro" \

	
#	-kernel build/kernel/arch/x86/boot/bzImage -append "console=tty0 root=UUID=6be5285a-115c-4d6c-9de5-2298b865ccd6 ro" \
#	-initrd initrd.img \


#	-enable-kvm \
#	-vga virtio -display gtk,zoom-to-fit=on,gl=on \
