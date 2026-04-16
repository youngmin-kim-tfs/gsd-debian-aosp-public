#!/bin/bash
set -x # enable printing

# Initialize image file
ROOTDIR=rootfs
OUTIMG=min-debian.img

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
HOSTNAME=debian
echo ${HOSTNAME} > "${ROOTDIR}"/etc/hostname
cat << EOF > "${ROOTDIR}"/ect/hosts
127.0.0.1	localhost
127.0.1.1	${HOSTNAME}
EOF

# Install base packages under chroot
ENV="env DEBIAN_FRONTEND=noninteractive LC_ALL=C"

BASE_PKG=" \
    util-linux \
    sudo procps udev \
    parted dosfstools e2fsprogs exfatprogs usbutils \
    iproute2 network-manager \
    less vim dialog \
    locales systemd-sysv \
    weston mesa-utils wayland-utils libxcb-cursor0 \
    grub-efi plymouth \
    linux-image-amd64 \
    tpm2-tools mokutil sbsigntool uuid-runtime efivar \
"

${ENV} chroot "${ROOTDIR}" apt -y install ${BASE_PKG}

# Install GRUB
${ENV} chroot "${ROOTDIR}" grub-install --target=x86_64-efi \
                              --removable \
                              --recheck \
                              --no-nvram \
                              --disable-shim-lock \
                              --uefi-secure-boot

# Generate PK, KEK, db (*.key, *.crt, *.der, *.esl, *.auth)
PK_UUID=$(uuidgen)
openssl req -newkey rsa:4096 -nodes -keyout PK-${PK_UUID}.key -new -x509 \
  -sha256 -days 3650 -out PK-${PK_UUID}.crt -subj "/CN=GSD Platform Key/"
openssl x509 -outform DER -in PK-${PK_UUID}.crt -out PK-${PK_UUID}.der
cert-to-efi-sig-list -g ${PK_UUID} PK-${PK_UUID}.crt PK-${PK_UUID}.esl
sign-efi-sig-list -k PK-${PK_UUID}.key -c PK-${PK_UUID}.crt PK PK-${PK_UUID}.esl PK-${PK_UUID}.auth

KEK_UUID=$(uuidgen)
openssl req -newkey rsa:4096 -nodes -keyout KEK-${KEK_UUID}.key -new -x509 \
  -sha256 -days 3650 -out KEK-${KEK_UUID}.crt -subj "/CN=GSD Key Exchange Key/"
openssl x509 -outform DER -in KEK-${KEK_UUID}.crt -out KEK-${KEK_UUID}.der
cert-to-efi-sig-list -g ${KEK_UUID} KEK-${KEK_UUID}.crt KEK-${KEK_UUID}.esl
sign-efi-sig-list -k PK-${PK_UUID}.key -c PK-${PK_UUID}.crt KEK KEK-${KEK_UUID}.esl KEK-${KEK_UUID}.auth

DB_UUID=$(uuidgen)
openssl req -newkey rsa:4096 -nodes -keyout db-${DB_UUID}.key -new -x509 \
  -sha256 -days 3650 -out db-${DB_UUID}.crt -subj "/CN=GSD Database key/"
openssl x509 -outform DER -in db-${DB_UUID}.crt -out db-${DB_UUID}.der
cert-to-efi-sig-list -g ${DB_UUID} db-${DB_UUID}.crt db-${DB_UUID}.esl
sign-efi-sig-list -k KEK-${KEK_UUID}.key -c KEK-${KEK_UUID}.crt db db-${DB_UUID}.esl db-${DB_UUID}.auth

# TEMPORARY: copy these keys to /boot/efi for Secure Boot setup
cp PK-${PK_UUID}.* "${ROOTDIR}"/boot/efi/
cp KEK-${KEK_UUID}.* "${ROOTDIR}"/boot/efi/
cp db-${DB_UUID}.* "${ROOTDIR}"/boot/efi/

# For GRUB, remove Debian sig and sign with custom db.key
GRUB="${ROOTDIR}"/boot/efi/EFI/BOOT/grubx64.efi
sbattach --remove "${GRUB}"
sbsign --key db-${DB_UUID}.key --cert db-${DB_UUID}.crt \
       --output "${GRUB}" \
       "${GRUB}"

# For kernel, remove Debian sig and sign with custom db.key
KERNEL=$(ls ${ROOTDIR}/boot/vmlinuz*)
sbattach --remove "${KERNEL}"
sbsign --key db-${DB_UUID}.key --cert db-${DB_UUID}.crt \
       --output "${KERNEL}" \
       "${KERNEL}"

# Point to grubx64.efi
chroot "${ROOTDIR}" mv /boot/efi/EFI/BOOT/BOOTX64.EFI /boot/efi/EFI/BOOT/shimx64.efi
chroot "${ROOTDIR}" cp /boot/efi/EFI/BOOT/grubx64.efi /boot/efi/EFI/BOOT/BOOTX64.efi

sed -i "${ROOTDIR}"/etc/default/grub \
    -e 's|\(GRUB_TIMEOUT\)=.*|\1=0|g' \
    -e 's|\(GRUB_CMDLINE_LINUX_DEFAULT\)="\(.*\)"|\1="\2 systemd.show_status=0 splash"|g'

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

# Copy the overlay
cp -r overlay-weston/* "${ROOTDIR}"/

# Install Kiosk session service
chroot "${ROOTDIR}" mkdir -p /etc/systemd/system/graphical.target.wants
chroot "${ROOTDIR}" ln -s /etc/systemd/system/kiosk-session.service \
  /etc/systemd/system/graphical.target.wants/kiosk-session.service
chroot "${ROOTDIR}" chmod 644 /etc/systemd/system/kiosk-session.service

# Install Weston service
chroot "${ROOTDIR}" mkdir -p /home/kiosk/.config/systemd/user/kiosk-session.target.wants
chroot "${ROOTDIR}" ln -s /home/kiosk/.config/systemd/user/weston.service \
  /home/kiosk/.config/systemd/user/kiosk-session.target.wants/weston.service

# Generate TLS key and cert for RDP
chroot "${ROOTDIR}" openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 \
  -out /home/kiosk/.config/rdp/rdp.key
chroot "${ROOTDIR}" chmod 755 /home/kiosk/.config/rdp/rdp-crt.sh
chroot "${ROOTDIR}" cd /home/kiosk/.config/rdp && ./rdp-crt.sh

# Set ownership to kiosk:kiosk
chroot "${ROOTDIR}" chown -R kiosk:kiosk /home/kiosk/.config

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

# Board-specific configurations
source seqstudio/seqstudio.sh

exit

# Clean up
rm db-*.*
rm KEK-*.*
rm PK-*.*

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
