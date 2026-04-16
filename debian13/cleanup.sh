#!/bin/bash
set -x

umount -R rootfs
#umount rootfs/data
#umount rootfs/boot/efi
#umount rootfs/dev/pts
#umount rootfs/dev
#umount rootfs/proc
#umount rootfs/run
#umount rootfs/sys
#uount rootfs/tmp
#umount rootfs/boot
#umount rootfs

lvchange -an vg0/root
lvchange -an vg0/data
vgchange -an vg0
cryptsetup close cryptroot

losetup -d /dev/loop0

lsblk -f
losetup -a
