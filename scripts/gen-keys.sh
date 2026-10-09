#!/bin/bash
# Genera el par RS256 en ./keys, en formato PKCS#8, que es el que leen los servicios.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p keys
if [ -f keys/jwt-private.pem ]; then
  echo "Ya existen llaves en ./keys. Borralas a mano si quieres regenerarlas."
  exit 0
fi
openssl genpkey -algorithm RSA -out keys/jwt-private.pem -pkeyopt rsa_keygen_bits:2048
openssl rsa -in keys/jwt-private.pem -pubout -out keys/jwt-public.pem
chmod 600 keys/jwt-private.pem
echo "Llaves creadas en ./keys (no se suben a git)."
