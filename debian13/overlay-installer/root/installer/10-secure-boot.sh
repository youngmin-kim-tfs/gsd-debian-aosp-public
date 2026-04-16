#!/bin/bash
set -x # enable printing

##############################
echo '#########################################'
echo 'Enroll PK, KEK, and db from UEFI setting!'
echo ' - Enable Secure Boot'
echo ' - Set to 'Setup mode' (or custom)'
echo ' - Enroll keys in this order:'
echo '   - db'
echo '   - KEK'
echo '   - PK'
echo '#########################################'
exit 0


##############################
# Check if in SecureBoot SetupMode
SECURE_BOOT_ON=$(( $(efivar -d -n $(efivar -l | grep 'SecureBoot')) ))
if (( SECURE_BOOT_ON == 0 )); then
    echo "Secure Boot is off"
fi

SETUP_MODE_ON=$(( $(efivar -d -n $(efivar -l | grep 'SetupMode')) ))
if (( SETUP_MODE_ON == 0 )); then
    echo "SetupMode is off."
    echo "Turn the SetupMode on from UEFI setting"
    exit 1
fi

##############################
# Enroll db
if ! efi-updatevar -f db.auth db; then
    echo "Error: failed to update db"
    exit 1
fi
echo "db updated successfully."

##############################
# Enroll KEK
if ! efi-updatevar -f KEK.auth KEK; then
    echo "Error: failed to update KEK"
    exit 1
fi
echo "KEK updated successfully."
    
##############################
# Enroll PK
if ls /sys/firmare/efi/efivars/PK-* >/dev/null 2>&1; then
    chattr -i /sys/firmware/efi/efivars/PK-*
fi
if ! efi-updatevar -f PK.auth PK; then
    echo "Error: failed to update PK"
    exit 1
fi
echo "PK updated successfully."

##############################
# Check the values
efi-readvar -v db
efi-readvar -v KEK
efi-readvar -v PK

