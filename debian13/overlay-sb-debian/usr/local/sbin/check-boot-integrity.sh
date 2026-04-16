#!/bin//bash
set -euo pipefail

BASELINE="/root/pcr-baseline.txt"
CURRENT=$(mktemp)

tpm2_pcrread sha256:0,1,2,3,4,5,6,7 > "${CURRENT}"

if diff -q "${BASELINE}" "${CURRENT}" > /dev/null 2>&1; then
    echo "PASS: Boot integrity verified by PCR values"
    rm -f "${CURRENT}}"
    exit 0
else
    echo "FAIL: Boot integrity failed by PCR values"
    rm -f "${CURRENT}"
    exit 1
fi
