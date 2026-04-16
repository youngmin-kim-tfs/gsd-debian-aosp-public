#!/bin/bash
set -x

# Check if TPM2 is supported
if [ ! -c /dev/tpm0 ] || [ ! -c /dev/tpmrm0 ]; then
    echo "No TPM device detected. Skipping LUKS TPM binds."
    exit 1
fi

PART=/dev/sda3
ROOT=/dev/vg0/root


# Bind with TPM with PCR0,2,7 (4 excluded)
systemd-cryptenroll --wipe-slot=tpm2 "${PART}"
systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+2+7 "${PART}" --unlock-key-file=luks.key
systemd-cryptenroll "${PART}"


# Open LUKS
cryptsetup open --key-file=luks.key "${PART}" cryptroot


# Wait for root folder
while [ ! -b "${ROOT}" ]; do
    sleep 2
done


# Mount required folders
mount /dev/vg0/root /mnt
mount /dev/sda2 /mnt/boot
mount /dev/sda1 /mnt/boot/efi
mount --bind /dev /mnt/dev
mount --bind /dev/pts /mnt/dev/pts
mount --bind /proc /mnt/proc
mount --bind /sys /mnt/sys
mount --bind /run /mnt/run


# Record pcr measures for debug
chroot /mnt /bin/bash -c "tpm2_pcrread sha256:0,2,4,7 > /home/kiosk/pcrread.usb"


# Rebuild initramfs
chroot /mnt dracut -f



# Clean up
umount -R /mnt
lvchange -a n vg0/root
vgchange -a n vg0
cryptsetup close cryptroot


# Add a recovery key
systemd-cryptenroll --wipe-slot=recovery "${PART}"
systemd-cryptenroll --unlock-key-file=luks.key --recovery-key "${PART}" > recovery.key
# Print recovery key
echo "# recovery-key:" "$(cat recovery.key)"


# Change or remove the default password:
# Change the default password
cryptsetup luksChangeKey --key-file=luks.key "${PART}"
# Remove the default password
#systemd-cryptenroll --wipe-slot=password "${PART}"



# To add new passwrod
#cryptsetup luksAddKey --key-file=luks.key "${PART}"

# To change password
#cryptsetup luksChangeKey --key-file=luks.key "${PART}"

# To remove enrolled slot
#systemd-cryptenroll --wipe-slot=1 "${PART}"


