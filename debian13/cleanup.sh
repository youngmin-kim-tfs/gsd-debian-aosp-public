#!/bin/bash
set -x

umount rootfs/boot/efi
umount rootfs/dev/pts
umount rootfs/dev
umount rootfs/proc
umount rootfs/run
umount rootfs/sys
umount rootfs/tmp
umount rootfs

losetup -d /dev/loop0

lsblk -f
losetup -a
