#!/bin/bash
set -x # enable printing

ROOTDIR=rootfs
OUTIMG=debian13.img

rm -rf "${ROOTDIR}"
rm -f "${OUTIMG}"

mkdir -p "${ROOTDIR}"
dd if=/dev/zero of="${OUTIMG}" bs=1M count=8192 status=progress

LOOPDEV=$(losetup --show -f "${OUTIMG}") # /dev/loop0

parted -s ${LOOPDEV} mklabel gpt
parted -s ${LOOPDEV} mkpart esp fat32 8MiB 512MiB
parted -s ${LOOPDEV} mkpart rootfs ext4 512MiB 6144MiB
parted -s ${LOOPDEV} mkpart data ext4 6144MiB 100%
parted -s ${LOOPDEV} set 1 esp on
parted -s ${LOOPDEV} print

DEVICES=($(lsblk -l -n -p -o NAME "${LOOPDEV}"))
EFIPART="${DEVICES[1]}" # /dev/loop0p1
ROOTPART="${DEVICES[2]}" # /dev/loop0p2
DATAPART="${DEVICES[3]}" # /dev/loop0p3

mkfs.vfat -F 32 "${EFIPART}"
mkfs.ext4 -F -L rootfs "${ROOTPART}"
mkfs.ext4 -F -L data "${DATAPART}"

losetup -a
lsblk -f

mount "${ROOTPART}" "${ROOTDIR}"
mkdir -p "${ROOTDIR}"/boot/efi
mount "${EFIPART}" "${ROOTDIR}"/boot/efi

debootstrap \
  --arch=amd64 \
  --variant=minbase \
  --components "main" \
  trixie "${ROOTDIR}"

mount --bind /dev "${ROOTDIR}"/dev
mount --bind /run "${ROOTDIR}"/run
chroot "${ROOTDIR}" mount none -t devpts /dev/pts
chroot "${ROOTDIR}" mount none -t proc /proc
chroot "${ROOTDIR}" mount none -t sysfs /sys
chroot "${ROOTDIR}" mount none -t tmpfs /tmp

chroot "${ROOTDIR}" echo "debian" > /etc/hostname

ROOT_UUID=$(blkid -s UUID -o value "${ROOTPART}")
EFI_UUID=$(blkid -s UUID -o value "${EFIPART}")
DATA_UUID=$(blkid -s UUID -o value "${DATAPART}")

cat <<EOF > "${ROOTDIR}"/etc/fstab
# <file system>     <mount point> <type> <options>  <dump> <pass>
UUID="${ROOT_UUID}" /             ext4   defaults   0      1
UUID="${EFI_UUID}"  /boot/efi     vfat   umask=0077 0      2
UUID="${DATA_UUID}" /data         ext4   defaults   0      1
EOF

ENV="env DEBIAN_FRONTEND=noninteractive LC_ALL=C"
PACKAGES="util-linux vim parted procps dialog udev sudo \
    dosfstools e2fsprogs exfatprogs usbutils \
    net-tools openssh-server openssh-client \
    systemd-sysv \
    gdm3 \
    gnome-terminal gnome-shell-extensions dconf-editor \
    network-manager-gnome \
    grub-efi linux-image-amd64"

${ENV} chroot "${ROOTDIR}" apt -y install ${PACKAGES}

${ENV} chroot "${ROOTDIR}" grub-install --target=x86_64-efi \
                              --removable \
                              --recheck \
                              --no-nvram

chroot "${ROOTDIR}" update-grub

chroot "${ROOTDIR}" useradd -m -d /home/debian -s /bin/bash debian
chroot "${ROOTDIR}" gpasswd -a debian sudo
chroot "${ROOTDIR}" usermod -aG sudo debian
chroot "${ROOTDIR}" passwd --delete root
chroot "${ROOTDIR}" passwd --delete debian

# Copy the Debian extensions
mkdir -p "${ROOTDIR}"/usr/share/gnome-shell/extensions/
cp -r extensions/* "${ROOTDIR}"/usr/share/gnome-shell/extensions/

umount "${ROOTDIR}"/boot/efi
umount "${ROOTDIR}"/dev/pts
umount "${ROOTDIR}"/dev
umount "${ROOTDIR}"/proc
umount "${ROOTDIR}"/run
umount "${ROOTDIR}"/sys
umount "${ROOTDIR}"/tmp
umount "${ROOTDIR}"

losetup -d "${LOOPDEV}"

