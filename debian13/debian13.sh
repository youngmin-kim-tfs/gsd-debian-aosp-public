#!/bin/bash
set -x # enable printing

# Initialize image file
ROOTDIR=rootfs
OUTIMG=debian13.img

rm -rf "${ROOTDIR}"
rm -f "${OUTIMG}"

mkdir -p "${ROOTDIR}"
dd if=/dev/zero of="${OUTIMG}" bs=1M count=8192 status=progress


# Set up loop device and partitions
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


# Minimum Debian bootstraping
mount "${ROOTPART}" "${ROOTDIR}"
debootstrap \
    --arch=amd64 \
    --variant=minbase \
    --components "main" \
    trixie \
    "${ROOTDIR}"


# Prepare and mount boot partition
mkdir -p "${ROOTDIR}"/boot/efi
mount "${EFIPART}" "${ROOTDIR}"/boot/efi

# Prepare /data
mkdir -p "${ROOTDIR}"/data
mount "${DATAPART}" "${ROOTDIR}"/data

# Bind with host for further installation
mount --bind /dev "${ROOTDIR}"/dev
mount --bind /run "${ROOTDIR}"/run
chroot "${ROOTDIR}" mount none -t devpts /dev/pts
chroot "${ROOTDIR}" mount none -t proc /proc
chroot "${ROOTDIR}" mount none -t sysfs /sys
chroot "${ROOTDIR}" mount none -t tmpfs /tmp


# Set hostname
chroot "${ROOTDIR}" echo "debian" > /etc/hostname


# Install base packages under chroot
ENV="env DEBIAN_FRONTEND=noninteractive LC_ALL=C"

BASE_PKG=" \
    util-linux \
    sudo procps udev \
    parted dosfstools e2fsprogs exfatprogs usbutils \
    iproute2 iputils-ping openssh-server telnet net-tools \
    vim dialog \
    grub-efi \
    linux-image-amd64 \
    \
    gdm3 \
    gnome-terminal \
    network-manager-gnome \
    gnome-shell-extensions \
    dconf-editor \
"

${ENV} chroot "${ROOTDIR}" apt -y install ${BASE_PKG}

# Install GRUB
${ENV} chroot "${ROOTDIR}" grub-install --target=x86_64-efi \
                              --removable \
                              --recheck \
                              --no-nvram
chroot "${ROOTDIR}" update-grub

# Set default locale
chroot "${ROOTDIR}" sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
chroot "${ROOTDIR}" /sbin/locale-gen
chroot "${ROOTDIR}" /sbin/update-locale LANG=en_US.UTF-8

# Create a kiosk user and disable root password
chroot "${ROOTDIR}" groupadd -g 1000 kiosk
chroot "${ROOTDIR}" useradd -g 1000 -m -d /home/kiosk -s /bin/bash kiosk
chroot "${ROOTDIR}" usermod -aG sudo kiosk
chroot "${ROOTDIR}" passwd --delete kiosk
chroot "${ROOTDIR}" passwd --delete root

# Prepare /data folder with 2775: u=rwx,g=rwx,g+s,o=rx
chroot "${ROOTDIR}" chown root:kiosk /data
chroot "${ROOTDIR}" chmod 2775 /data
chroot "${ROOTDIR}" mkdir -p /data/opt
chroot "${ROOTDIR}" mkdir -p /data/srv
chroot "${ROOTDIR}" mkdir -p /data/shared
chroot "${ROOTDIR}" ln -s /data/shared /shared

# Copy the overlay and enable kiosk mode
cp -r overlay/* "${ROOTDIR}"/
chroot "${ROOTDIR}" chmod 644 /etc/dconf/db/local.d/00-kiosk
chroot "${ROOTDIR}" chmod 644 /etc/gdm3/daemon.conf
chroot "${ROOTDIR}" chmod 644 /etc/xdg/autostart/kiosk.desktop
chroot "${ROOTDIR}" chmod 644 /usr/share/gnome-shell/extensions/kiosk-shell@kiosk.shell/extension.js
chroot "${ROOTDIR}" chmod 644 /usr/share/gnome-shell/extensions/kiosk-shell@kiosk.shell/metadata.json
chroot "${ROOTDIR}" dconf update

# Configure /etc/fstab for disk mounts. /opt and /srv
ROOT_UUID=$(blkid -s UUID -o value "${ROOTPART}")
EFI_UUID=$(blkid -s UUID -o value "${EFIPART}")
DATA_UUID=$(blkid -s UUID -o value "${DATAPART}")
cat <<EOF > "${ROOTDIR}"/etc/fstab
# <file system>     <mount point> <type> <options>  <dump> <pass>
UUID="${ROOT_UUID}" /             ext4   defaults   0      1
UUID="${EFI_UUID}"  /boot/efi     vfat   umask=0077 0      2
UUID="${DATA_UUID}" /data         ext4   defaults   0      2
/data/opt           /opt          none   bind       0      0
/data/srv           /srv          none   bind       0      0
EOF

## Board-specific configurations
source seqstudio/seqstudio.sh

#echo 'CHECKPOINT!'
#exit


# Clean up
umount "${ROOTDIR}"/data
umount "${ROOTDIR}"/boot/efi
umount "${ROOTDIR}"/dev/pts
umount "${ROOTDIR}"/dev
umount "${ROOTDIR}"/proc
umount "${ROOTDIR}"/run
umount "${ROOTDIR}"/sys
umount "${ROOTDIR}"/tmp
umount "${ROOTDIR}"

losetup -d "${LOOPDEV}"
