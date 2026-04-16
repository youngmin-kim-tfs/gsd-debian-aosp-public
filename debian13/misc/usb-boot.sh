#!/bin/bash
set -x # enable printing

ROOTDIR="rootfs"
mkdir -p "${ROOTDIR}"

OUTPUT=usb-boot.img
rm "${OUTPUT}"
dd if=/dev/zero of="${OUTPUT}" bs=1M count=1280 status=progress

device=$(losetup --show -f "${OUTPUT}")

parted -s ${device} mklabel gpt
parted -s ${device} mkpart esp fat32 8MiB 64MiB
parted -s ${device} mkpart primary ext4 64MiB 1024MiB
parted -s ${device} mkpart primary fat32 1024MiB 100%
parted -s ${device} set 1 esp on
parted -s ${device} print

mkfs.vfat -F 32 /dev/loop0p1
mkfs.ext4 -F -L rootfs /dev/loop0p2
mkfs.exfat -L data /dev/loop0p3
lsblk -f

mount /dev/loop0p2 "${ROOTDIR}"
debootstrap --arch=amd64 --variant=minbase trixie "${ROOTDIR}"

mkdir -p "${ROOTDIR}"/boot/efi

mount /dev/loop0p1 "${ROOTDIR}"/boot/efi
mount --bind /dev "${ROOTDIR}"/dev
mount -t devpts /dev/pts "${ROOTDIR}"/dev/pts
mount -t proc proc "${ROOTDIR}"/proc
mount -t sysfs sysfs "${ROOTDIR}"/sys
mount -t tmpfs tmpfs "${ROOTDIR}"/tmp

ENV="env DEBIAN_FRONTEND=noninteractive LC_ALL=C"
PACKAGES="util-linux vim parted procps dialog udev \
    dosfstools e2fsprogs exfatprogs \
    net-tools openssh-server openssh-client \
    systemd-sysv \
    grub-efi linux-image-amd64"

${ENV} chroot "${ROOTDIR}" apt -y install ${PACKAGES} 

chroot "${ROOTDIR}" grub-install --target=x86_64-efi \
                                 --recheck \
                                 --debug \
                                 --no-nvram \
                                 --removable

sed -i "${ROOTDIR}/etc/default/grub" -e 's|\(GRUB_CMDLINE_LINUX_DEFAULT\)="\(.*\)"|\1="\2 init=/bin/bash"|g'

chroot "${ROOTDIR}" update-grub

chroot "${ROOTDIR}" df -h

umount ${ROOTDIR}/boot/efi
umount ${ROOTDIR}/dev/pts
umount ${ROOTDIR}/dev
umount ${ROOTDIR}/proc
umount ${ROOTDIR}/run
umount ${ROOTDIR}/sys
umount ${ROOTDIR}/tmp
umount ${ROOTDIR}
losetup -d /dev/loop0

