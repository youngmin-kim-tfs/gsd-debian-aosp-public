#!/bin/bash
set -x

IMAGE=/data/sb-debian.img
DISK=/dev/sda
PART=/dev/sda3
DATA=/dev/vg0/data
MAPPER=cryptroot
LUKS_KEY=luks.key


# Copy the image to main disk
dd if="${IMAGE}" of="${DISK}" bs=4M status=progress


# Resize the last partition
parted -s -f -a optimal "${DISK}" resizepart 3 100%
cryptsetup isLuks "${PART}"
cryptsetup open --type luks2 "${PART}" "${MAPPER}" --key-file "${LUKS_KEY}"
cryptsetup resize "${MAPPER}" --key-file "${LUKS_KEY}"
pvresize /dev/mapper/"${MAPPER}"
lvextend --resizefs --extents +100%FREE "${DATA}"
#resize2fs "${DATA}"

vgchange -an vg0
cryptsetup close "${MAPPER}"
