#!/bin/bash
set -x # enable printing

# Initialize image file
OUT=out
ROOTDIR=rootfs
IMAGE="${OUT}"/installer.img
DEBIAN="${OUT}"/sb-debian.img

rm -rf "${ROOTDIR}"
rm -f "${IMAGE}"

mkdir -p "${ROOTDIR}"
dd if=/dev/zero of="${IMAGE}" bs=1M count=16384 status=progress


# Set up loop device and partitions
LOOPDEV=$(losetup --show -f "${IMAGE}") # /dev/loop0

parted -s ${LOOPDEV} mklabel gpt
parted -s ${LOOPDEV} mkpart esp fat32 8MiB 512MiB
parted -s ${LOOPDEV} mkpart root ext4 512MiB 6144MiB
parted -s ${LOOPDEV} mkpart data ext4 6144MiB 100% 
parted -s ${LOOPDEV} set 1 esp on
parted -s ${LOOPDEV} print

DEVICES=($(lsblk -l -n -p -o NAME "${LOOPDEV}"))
EFIPART="${DEVICES[1]}" # /dev/loop0p1
ROOTPART="${DEVICES[2]}" # /dev/loop0p2
DATAPART="${DEVICES[3]}" # /dev/loop0p3


# Format the partitions
mkfs.vfat -F 32 "${EFIPART}"
mkfs.ext4 -F -L root "${ROOTPART}"
mkfs.ext4 -F -L data "${DATAPART}"


# Get UUID of all partitions
EFI_UUID=$(blkid -s UUID -o value "${EFIPART}")
ROOT_UUID=$(blkid -s UUID -o value "${ROOTPART}")
DATA_UUID=$(blkid -s UUID -o value "${DATAPART}")


# Mount folders for debian installation
mount "${ROOTPART}" "${ROOTDIR}"
mkdir -p "${ROOTDIR}"/boot/efi
mount "${EFIPART}" "${ROOTDIR}"/boot/efi
mkdir -p "${ROOTDIR}"/data
mount "${DATAPART}" "${ROOTDIR}"/data


# Minimum Debian bootstraping
debootstrap \
    --arch=amd64 \
    --variant=minbase \
    --components "main" \
    trixie \
    "${ROOTDIR}"


# Bind required folders from host
mount --bind /dev "${ROOTDIR}"/dev
mount --bind /run "${ROOTDIR}"/run
chroot "${ROOTDIR}" mount none -t devpts /dev/pts
chroot "${ROOTDIR}" mount none -t proc /proc
chroot "${ROOTDIR}" mount none -t sysfs /sys
chroot "${ROOTDIR}" mount none -t tmpfs /tmp


# Set hostname
HOSTNAME=debian
echo ${HOSTNAME} > "${ROOTDIR}"/etc/hostname
cat << EOF > "${ROOTDIR}"/etc/hosts
127.0.0.1	localhost
127.0.1.1	${HOSTNAME}
EOF


# Install base packages under chroot
ENV="env DEBIAN_FRONTEND=noninteractive LC_ALL=C"
BASE_PKG=" \
    util-linux \
    sudo procps udev \
    parted dosfstools e2fsprogs exfatprogs usbutils \
    iproute2 network-manager openssh-client \
    less vim dialog \
    locales systemd-sysv \
    weston mesa-utils wayland-utils libxcb-cursor0 \
    grub-efi plymouth \
    linux-image-amd64 \
    tpm2-tools mokutil sbsigntool uuid-runtime efivar efitools \
    lvm2 cryptsetup dracut \
"
${ENV} chroot "${ROOTDIR}" apt -y install ${BASE_PKG}


# Install GRUB
${ENV} chroot "${ROOTDIR}" grub-install --target=x86_64-efi \
                              --removable \
                              --recheck \
                              --no-nvram \
                              --disable-shim-lock \
                              --uefi-secure-boot


# Sign the GRUB bootloader with the same db.key for consistent PCR7
GRUB="${ROOTDIR}"/boot/efi/EFI/BOOT/grubx64.efi
sbattach --remove "${GRUB}"
sbsign --key "${OUT}"/db.key --cert "${OUT}"/db.pem \
       --output "${GRUB}" \
       "${GRUB}"

# Sign the kernel with the same db.key
KERNEL=$(ls "${ROOTDIR}"/boot/vmlinuz*)
sbattach --remove "${KERNEL}"
sbsign --key "${OUT}"/db.key --cert "${OUT}"/db.pem \
       --output "${KERNEL}" \
       "${KERNEL}"

chroot "${ROOTDIR}" mv /boot/efi/EFI/BOOT/BOOTX64.EFI /boot/efi/EFI/BOOT/shimx64.efi
chroot "${ROOTDIR}" cp /boot/efi/EFI/BOOT/grubx64.efi /boot/efi/EFI/BOOT/BOOTX64.efi


# Set default locale
chroot "${ROOTDIR}" sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
chroot "${ROOTDIR}" /sbin/locale-gen
chroot "${ROOTDIR}" /sbin/update-locale LANG=en_US.UTF-8


# Disable root password
chroot "${ROOTDIR}" passwd --delete root


# Copy the overlay
cp -r overlay-installer/* "${ROOTDIR}"/


# Copy PK, KEK, db certs to EFI partition
cp "${OUT}"/PK.der "${ROOTDIR}"/boot/efi/
cp "${OUT}"/KEK.der "${ROOTDIR}"/boot/efi/
cp "${OUT}"/db.der "${ROOTDIR}"/boot/efi/
# Copy PK, KEK, db auth for additional installation option
cp "${OUT}"/PK.auth "${ROOTDIR}"/root/installer/
cp "${OUT}"/KEK.auth "${ROOTDIR}"/root/installer/
cp "${OUT}"/db.auth "${ROOTDIR}"/root/installer/


# Copy LUKS key installatiooon
cp "${OUT}"/luks.key "${ROOTDIR}"/root/installer/


# Copy the image file to data partition
cp "${DEBIAN}" "${ROOTDIR}"/data/


# Install Kiosk session service
chroot "${ROOTDIR}" mkdir -p /etc/systemd/system/graphical.target.wants
chroot "${ROOTDIR}" ln -s /etc/systemd/system/kiosk-session.service \
  /etc/systemd/system/graphical.target.wants/kiosk-session.service
chroot "${ROOTDIR}" chmod 644 /etc/systemd/system/kiosk-session.service


# Install Weston service
chroot "${ROOTDIR}" mkdir -p /root/.config/systemd/user/kiosk-session.target.wants
chroot "${ROOTDIR}" ln -s /root/.config/systemd/user/weston.service \
  /root/.config/systemd/user/kiosk-session.target.wants/weston.service


# Configure /etc/fstab for disk mounts. /opt and /srv
cat <<EOF > "${ROOTDIR}"/etc/fstab
# <file system>    <mount point> <type> <options>  <dump> <pass>
UUID=${EFI_UUID}   /boot/efi     vfat   umask=0077 0      2
UUID=${ROOT_UUID}  /             ext4   defaults   0      1
UUID=${DATA_UUID}  /data         ext4   defaults   0      2
EOF


# Configure GRUB and update
sed -i "${ROOTDIR}"/etc/default/grub \
    -e 's|\(GRUB_TIMEOUT\)=.*|\1=0|g' \
    -e 's|\(GRUB_CMDLINE_LINUX_DEFAULT\)="\(.*\)"|\1="\2 systemd.show_status=0 splash"|g'

chroot "${ROOTDIR}" update-grub


# Final cleanup
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

