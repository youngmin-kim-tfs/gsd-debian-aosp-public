#!/bin/bash
set -x # enable printing


OUT="out"
mkdir -p "${OUT}"


##############################
# Generate PK.key and PK.pem
openssl req -newkey rsa:4096 -nodes -keyout "${OUT}"/PK.key -new -x509 \
  -sha256 -days 3650 -out "${OUT}"/PK.pem -subj "/CN=GSD Platform Key/"
# PK.pem -> PK.der
openssl x509 -outform DER -in "${OUT}"/PK.pem -out "${OUT}"/PK.der
# PK.esl
cert-to-efi-sig-list -g $(uuidgen) "${OUT}"/PK.pem "${OUT}"/PK.esl
# Signing PK.esl -> PK.auth
sign-efi-sig-list -k "${OUT}"/PK.key -c "${OUT}"/PK.pem PK "${OUT}"/PK.esl "${OUT}"/PK.auth


##############################
# Generate PK-none.esl and PK-none.auth
touch "${OUT}"/PK-none.esl
sign-efi-sig-list -k "${OUT}"/PK.key -c "${OUT}"/PK.pem PK "${OUT}"/PK-none.esl "${OUT}"/PK-none.auth


##############################
# Generate KEK.key and KEK.pem
openssl req -newkey rsa:4096 -nodes -keyout "${OUT}"/KEK.key -new -x509 \
  -sha256 -days 3650 -out "${OUT}"/KEK.pem -subj "/CN=GSD Key Exchange Key/"
# KEK.pem -> KEK.der
openssl x509 -outform DER -in "${OUT}"/KEK.pem -out "${OUT}"/KEK.der
# KEK.esl
cert-to-efi-sig-list -g $(uuidgen) "${OUT}"/KEK.pem "${OUT}"/KEK.esl
# Append any other KEK's
# cat KEK1.esl KEK2.esl KEK3.esl > KEK.esl
# Signing KEK.els with PK.key and PK.pem -> KEK.auth
sign-efi-sig-list -k "${OUT}"/PK.key -c "${OUT}"/PK.pem KEK "${OUT}"/KEK.esl "${OUT}"/KEK.auth


##############################
# Genrate db.key and db.pem
openssl req -newkey rsa:4096 -nodes -keyout "${OUT}"/db.key -new -x509 \
  -sha256 -days 3650 -out "${OUT}"/db.pem -subj "/CN=GSD Database key/"
# db.pem -> db.der
openssl x509 -outform DER -in "${OUT}"/db.pem -out "${OUT}"/db.der
# db.esl
cert-to-efi-sig-list -g $(uuidgen) "${OUT}"/db.pem "${OUT}"/db.esl
# Append other db.esl
# cat db1.esl db2.esl > db.esl
# Signing db.els with KEK.key and KEK.pem -> db.auth
sign-efi-sig-list -k "${OUT}"/KEK.key -c "${OUT}"/KEK.pem db "${OUT}"/db.esl "${OUT}"/db.auth

