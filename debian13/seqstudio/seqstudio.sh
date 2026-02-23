#!/bin/bash
set -x # enable printing

pwd

cp -r seqstudio/overlay/* "${ROOTDIR}"/

# Copy the NIC renaming script
chroot "${ROOTDIR}" chmod 755 /usr/local/sbin/nic-namer.sh

# Copy the nic-namer.service and enable it
chroot "${ROOTDIR}" ln -s /etc/systemd/system/nic-namer.service \
  /etc/systemd/system/multi-user.target.wants/nic-namer.service
chroot "${ROOTDIR}" chmod 644 /etc/systemd/system/nic-namer.service

# Copy the instrumentserver.service and enable it
chroot "${ROOTDIR}" ln -s /etc/systemd/system/instrumentserver.service \
  /etc/systemd/system/multi-user.target.wants/instrumentserver.service
chroot "${ROOTDIR}" chmod 644 /etc/systemd/system/instrumentserver.service

# Create users
# Placeholder for instrument specific user creation

# SeqStudio specific package
chroot "${ROOTDIR}" dpkg --add-architecture i386
chroot "${ROOTDIR}" apt update
chroot "${ROOTDIR}" apt -y install \
    libc6:i386 \
    libstdc++6:i386 \
    default-jre \
    python3-zombie-telnetlib \
    python3-numpy

# Create SeqStudio specific directories
chroot "${ROOTDIR}" mkdir -p /opt/Monarch
