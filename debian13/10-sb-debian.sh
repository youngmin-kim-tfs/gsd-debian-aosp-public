#!/bin/bash
set -x # enable printing

# Initialize image file
OUT=out
ROOTDIR=rootfs
IMAGE="${OUT}"/sb-debian.img

rm -rf "${ROOTDIR}"
rm -f "${IMAGE}"

mkdir -p "${ROOTDIR}"
dd if=/dev/zero of="${IMAGE}" bs=1M count=8192 status=progress


# Set up loop device and partitions
LOOPDEV=$(losetup --show -f "${IMAGE}") # /dev/loop0

parted -s ${LOOPDEV} mklabel gpt
parted -s ${LOOPDEV} mkpart esp fat32 8MiB 512MiB
parted -s ${LOOPDEV} mkpart boot ext4 512MiB 1024MiB
parted -s ${LOOPDEV} mkpart crypt ext4 1024MiB 100%
parted -s ${LOOPDEV} set 1 esp on
parted -s ${LOOPDEV} set 2 lvm on
parted -s ${LOOPDEV} print

DEVICES=($(lsblk -l -n -p -o NAME "${LOOPDEV}"))
EFIPART="${DEVICES[1]}" # /dev/loop0p1
BOOTPART="${DEVICES[2]}" # /dev/loop0p2
CRYPTPART="${DEVICES[3]}" # /dev/loop0p3


# Prepare LUKS: device=crypt, vg0-root, vg0-data
LUKS_KEY="${OUT}"/luks.key
#dd if=/dev/urandom of="${LUKS_KEY}" bs=512 count=8
printf '%s' 'password' > "${LUKS_KEY}"
chmod 400 "${LUKS_KEY}"
cryptsetup luksFormat --batch-mode --type luks2 "${CRYPTPART}" "${LUKS_KEY}" 
cryptsetup open --type luks2 --key-file "${LUKS_KEY}" "${CRYPTPART}" cryptroot
cryptsetup -v status cryptroot

pvcreate /dev/mapper/cryptroot
vgcreate vg0 /dev/mapper/cryptroot
lvcreate -L 6G --name root vg0
lvcreate -l 100%FREE --name data vg0


# Format the partitions
mkfs.vfat -F 32 "${EFIPART}"
mkfs.ext4 -F -L boot "${BOOTPART}"
mkfs.ext4 -F /dev/vg0/root
mkfs.ext4 -F /dev/vg0/data


# Get UUID of all partitions
EFI_UUID=$(blkid -s UUID -o value "${EFIPART}")
BOOT_UUID=$(blkid -s UUID -o value "${BOOTPART}")
CRYPT_UUID=$(blkid -s UUID -o value "${CRYPTPART}")
ROOT_UUID=$(blkid -s UUID -o value /dev/mapper/vg0-root)
DATA_UUID=$(blkid -s UUID -o value /dev/mapper/vg0-data)


# Mount folders for debian installation
mount /dev/vg0/root "${ROOTDIR}"
mkdir -p "${ROOTDIR}"/boot
mount "${BOOTPART}" "${ROOTDIR}"/boot
mkdir -p "${ROOTDIR}"/boot/efi
mount "${EFIPART}" "${ROOTDIR}"/boot/efi
mkdir -p "${ROOTDIR}"/data
mount /dev/vg0/data "${ROOTDIR}"/data


# Minimum Debian bootstraping
debootstrap \
    --arch=amd64 \
    --variant=minbase \
    --components "main" \
    trixie \
    "${ROOTDIR}" http://mirrors.ocf.berkeley.edu/debian


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
    sbsigntool uuid-runtime efivar efitools \
    tpm2-tools libtss2-fapi1t64 libtpm2-pkcs11-tools libtpm2-pkcs11-1 opensc \
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


# For GRUB, remove Debian sig and sign with custom db.key
GRUB="${ROOTDIR}"/boot/efi/EFI/BOOT/grubx64.efi
sbattach --remove "${GRUB}"
sbsign --key "${OUT}"/db.key --cert "${OUT}"/db.pem \
       --output "${GRUB}" \
       "${GRUB}"

# For kernel, remove Debian sig and sign with custom db.key
KERNEL=$(ls "${ROOTDIR}"/boot/vmlinuz*)
sbattach --remove "${KERNEL}"
sbsign --key "${OUT}"/db.key --cert "${OUT}"/db.pem \
       --output "${KERNEL}" \
       "${KERNEL}"


# Point to grubx64.efi
chroot "${ROOTDIR}" mv /boot/efi/EFI/BOOT/BOOTX64.EFI /boot/efi/EFI/BOOT/shimx64.efi
chroot "${ROOTDIR}" cp /boot/efi/EFI/BOOT/grubx64.efi /boot/efi/EFI/BOOT/BOOTX64.efi


# Set default locale
chroot "${ROOTDIR}" sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
chroot "${ROOTDIR}" /sbin/locale-gen
chroot "${ROOTDIR}" /sbin/update-locale LANG=en_US.UTF-8


# Create a kiosk user and disable root password
chroot "${ROOTDIR}" groupadd -g 1000 kiosk
chroot "${ROOTDIR}" useradd -g 1000 -m -d /home/kiosk -s /bin/bash kiosk
chroot "${ROOTDIR}" usermod -aG sudo kiosk
chroot "${ROOTDIR}" passwd --delete kiosk
#chroot "${ROOTDIR}" passwd --delete root
chroot "${ROOTDIR}" /bin/bash -c 'echo "root:password" | chpasswd'


# Prepare /data folder with 2775: u=rwx,g=rwx,g+s,o=rx
chroot "${ROOTDIR}" chown root:kiosk /data
chroot "${ROOTDIR}" chmod 2775 /data
chroot "${ROOTDIR}" mkdir -p /data/opt
chroot "${ROOTDIR}" mkdir -p /data/srv
chroot "${ROOTDIR}" mkdir -p /data/shared
chroot "${ROOTDIR}" ln -s /data/shared /shared


# Copy the overlay
cp -r overlay-sb-debian/* "${ROOTDIR}"/


# PKCS#11
chroot "${ROOTDIR}" /bin/bash -c 'echo "TPM2_PKCS11_STORE=/etc/tpm2_pkcs11" >> /etc/environment'
chroot "${ROOTDIR}" mkdir -p /etc/tpm2_pkcs11
chroot "${ROOTDIR}" chown root:tss /etc/tpm2_pkcs11
chroot "${ROOTDIR}" 775 /etc/tpm2_pkcs11


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
chroot "${ROOTDIR}" /bin/bash -c "cd /home/kiosk/.config/rdp && ./rdp-crt.sh"


# Set ownership to kiosk:kiosk
chroot "${ROOTDIR}" chown -R kiosk:kiosk /home/kiosk/.config


# Copy the LUKS key file
mkdir -p "${ROOTDIR}"/etc/cryptsetup-keys.d
chroot "${ROOTDIR}" chmod 700 /etc/cryptsetup-keys.d
#cp "${LUKS_KEY}" "${ROOTDIR}"/etc/cryptsetup-keys.d/ #chroot "${ROOTDIR}" chmod 400 /etc/cryptsetup-keys.d/${LUKS_KEY}


# Configure /etc/crypttab
#cat <<EOF > "${ROOTDIR}"/etc/crypttab
#cryptroot UUID=${CRYPT_UUID} /etc/cryptsetup-keys.d/${LUKS_KEY} luks,tpm2-device=auto
#EOF
#cat <<EOF > "${ROOTDIR}"/etc/crypttab
#luks-${CRYPT_UUID} UUID=${CRYPT_UUID} none luks,tpm2-device=auto
#EOF


# Configure /etc/cryptsetup-initramfs/conf-hook
#sed -i "${ROOTDIR}"/etc/cryptsetup-initramfs/conf-hook \
#    -e 's|.*KEYFILE_PATTERN=.*|KEYFILE_PATTERN=/etc/cryptsetup-keys.d/'${LUKS_KEY}'|g'
#echo 'UMASK=0077' > "${ROOTDIR}"/etc/initramfs-tools/conf.d/umask


# Configure /etc/fstab for disk mounts. /opt and /srv
cat <<EOF > "${ROOTDIR}"/etc/fstab
# <file system>    <mount point> <type> <options>  <dump> <pass>
UUID=${EFI_UUID}   /boot/efi     vfat   umask=0077 0      2
UUID=${BOOT_UUID}  /boot         ext4   defaults   0      1
UUID=${ROOT_UUID}  /             ext4   defaults   0      1
UUID=${DATA_UUID}  /data         ext4   defaults   0      2
/data/opt          /opt          none   bind       0      0
/data/srv          /srv          none   bind       0      0
EOF

chroot "${ROOTDIR}" vgchange -ay
#chroot "${ROOTDIR}" update-initramfs -u -c -k all -v
KERNEL=$(ls "${ROOTDIR}"/lib/modules | tail -n1)


# Configure GRUB and update
#sed -i "${ROOTDIR}"/etc/default/grub \
#    -e 's|\(GRUB_TIMEOUT\)=.*|\1=0|g' \
#    -e 's|\(GRUB_CMDLINE_LINUX_DEFAULT\)="\(.*\)"|\1="\2 systemd.show_status=0 splash"|g' \
#    -e 's|\(GRUB_CMDLINE_LINUX\)="\(.*\)"|\1="cryptdevice=UUID='${CRYPT_UUID}':cryptroot root=/dev/vg0/root"|g'
#    -e 's|\(GRUB_CMDLINE_LINUX\)="\(.*\)"|\1="rd.auto rd.luks=1 rd.break SYSTEMD_SULOGIN_FORCE=1"|g'
sed -i "${ROOTDIR}"/etc/default/grub \
    -e 's|\(GRUB_TIMEOUT\)=.*|\1=5|g' \
    -e 's|\(GRUB_CMDLINE_LINUX_DEFAULT\)="\(.*\)"|\1="\2 systemd.show_status=0 splash"|g' \
    -e 's|\(GRUB_CMDLINE_LINUX\)="\(.*\)"|\1="rd.auto rd.luks=1"|g'

echo 'u tss - "tpm2 tss" /dev/null /usr/sbin/nologin' >> "${ROOTDIR}"/usr/lib/sysusers.d/basic.conf

chroot "${ROOTDIR}" dracut -f --kver $KERNEL
chroot "${ROOTDIR}" update-grub


# Apply any board-specific configurations
source seqstudio/seqstudio.sh


# Final clean up
umount "${ROOTDIR}"/data
umount "${ROOTDIR}"/boot/efi
umount "${ROOTDIR}"/dev/pts
umount "${ROOTDIR}"/dev
umount "${ROOTDIR}"/proc
umount "${ROOTDIR}"/run
umount "${ROOTDIR}"/sys
umount "${ROOTDIR}"/tmp
umount "${ROOTDIR}"/boot
umount "${ROOTDIR}"

lvchange -a n vg0/root
lvchange -a n vg0/data
vgchange -a n vg0
cryptsetup close cryptroot

losetup -d "${LOOPDEV}"

