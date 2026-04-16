#!/bin/bash
set -x

# Check if TPM2 is supported
if [ ! -c /dev/tpm0 ] || [ ! -c /dev/tpmrm0 ]; then
    echo "No TPM device detected. Skipping TPM2 PKCS#11"
    exit 1
fi

PART=/dev/sda3
ROOT=/dev/vg0/root


# Open LUKS
cryptsetup open --key-file=luks.key "${PART}" cryptroot
ret = $?
if [ $ret -ne 0 ]; then
    echo "Failed to open LUKS container"
    exit $ret
fi

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


# Initialize tpm persistent handles
mapfile -t HANDLES < <(tpm2_getcap handles-persistent 2>/dev/null | grep -Eo '0x[0-9a-fA-F]+')
for h in "${HANDLES[@]}"; do
    echo "evicting $h ..."
    tpm2_evictcontrol -C o -c "$h"
done

# Initialize pkcs stores
rm -f /mnt/etc/tpm2_pkcs11/*

# Create a new PKCS11 store at /etc/tpm2_pkcs11
chroot /mnt /bin/bash -c 'TPM2_PKCS11_STORE=/etc/tpm2_pkcs11 tpm2_ptool init'

# Create a new token in the store 1
chroot /mnt /bin/bash -c 'TPM2_PKCS11_STORE=/etc/tpm2_pkcs11 tpm2_ptool addtoken --pid=1 --label=tls --userpin=1234 --sopin=1234'

# Create a new key in the token, 'tls'
chroot /mnt /bin/bash -c 'TPM2_PKCS11_STORE=/etc/tpm2_pkcs11 tpm2_ptool addkey --algorithm=rsa2048 --label=tls --userpin=1234'

# To list all stores
# tpm2_ptool listprimaries
# tpm2_ptool listtokens --pid=<primary-id>
# tpm2_ptool listobjects --label=<token-label>
# To change userpin
# pkcs11-tool --module /usr/lib/x86_64-linux-gnu/pkcs11/libtpm2_pkcs11.so \
#             --label "tls" \
#             --login --pin "olduserpin" \
#             --change-pin --new-pin "newuserpin"
#
#
# TO list tokens/slots
# pkcs11-tool --module /usr/lib/x86_64-linux-gnu/pkcs11/libtpm2_pkcs11.so \
#             --list-token-slots
#
# To clear TPM2 lockout
# tpm2_dictionarylockout --clear-lockout
#
# To change userpin
# pkcs11-tool --module /usr/lib/x86_64-linux-gnu/pkcs11/libtpm2_pkcs11.so --label "label" --login --pin "oldpin" --change-pin --new-pin "newpin"
# To reset userpin
# pkcs11-tool --module /usr/lib/x86_64-linux-gnu/pkcs11/libtpm2_pkcs11.so --login --login-type so --so-pin "sopin" --init-pin --pin "newpin"# To change sopin
# pkcs11-tool --module /usr/lib/x86_64-linux-gnu/pkcs11/libtpm2_pkcs11.so --login --login-type so --so-pin "oldsopin" --change-pin --new-pin "newsopin"
#
# PKCS#11 config:
# name = TPM2
# library = /usr/lib/x86_64-linux-gnu/libtpm2_pkcs11.so
# slot = 0
#
# server:
#   ssl:
#     enabled: true
#     key-store-type: PKCS11
#     key-store: NONE
#     key-store-provider: SunPKCS11-TPM2-PKCS11
#     key-alias: <key-alias>
#     key-password: <user-pin>
#
#
#
#
#
#
# To encrypt/decrypt: e.g. WiFi, instrument user pins, smb credentials
#
# tpm2_createprimary -C o -c parent.ctx
# tpm2_create k-C parent.ctx -G aes128 -u key.pub -r key.priv
# tpm2_load -C primary.ctx -u key.pub -r key.priv -c key.ctx
# tpm2_encryptdecrypt -c key.ctx -o secret.enc secret.dat
# tpm2_encryptdecrypt -d -c key.ctx -o secret.dec secret.enc
#
# To create and persist
# tpm2_createprimary -C o -c parent.ctx
# tpm2_create -C parent.ctx -u key.pub -r key.priv
# tpm2_load -C parent.ctx -u key.pub -r key.priv -c key.ctx
# tpm2_evictcontrol -C o -c key.ctx 0x81000001
#
# To create with data
# tpm2_createprimary -C o -c parent.ctx
# tpm2_create -C parent.ctx -i data_to_seal.txt -u key.pub -r key.priv
# tpm2_load -C parent.ctx -u key.put -r key.priv -c key.ctx
# tpm2_evictcontrol -C o -c key.ctx 0x81000001
#
# To check
# tpm2_getcap handles-persistent
# tpm2_readpublic -c 0x81000001
#
# To remove
# tpm2_evictcontrol -C o -c 0x81000001
#
# To sign message.data
# tpm2_sign -c 0x81000001 -g sha256 -o message.sig message.dat
#
# To verify:
# tpm2_verifysignature -c 0x81000001 -g sha256 -s message.sig -m message.data
#
# To verify using OpenSSL (public key from tpm2 on server)
# openssl dgst -verify key.pub.pem -keyform pem -sha256 -signature sig.rsa
#


# Clean up
umount -R /mnt
lvchange -a n vg0/root
vgchange -a n vg0
cryptsetup close cryptroot

