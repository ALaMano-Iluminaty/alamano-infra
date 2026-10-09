#!/bin/bash
# Genera el par RS256 en ./keys, en formato PKCS#8, que es el que leen los servicios.
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v openssl >/dev/null 2>&1; then
  echo "ERROR: no encuentro openssl." >&2
  echo "  En Windows, corre este script desde Git Bash, que ya lo trae." >&2
  echo "  En Ubuntu: sudo apt-get install -y openssl" >&2
  exit 1
fi

mkdir -p keys
if [ -f keys/jwt-private.pem ] && [ -f keys/jwt-public.pem ]; then
  echo "Ya existen las llaves en ./keys. Borralas a mano si quieres regenerarlas."
  exit 0
fi

openssl genpkey -algorithm RSA -out keys/jwt-private.pem -pkeyopt rsa_keygen_bits:2048
openssl rsa -in keys/jwt-private.pem -pubout -out keys/jwt-public.pem

# La publica la leen los contenedores, que corren como usuario 'app', no como root.
chmod 644 keys/jwt-public.pem
chmod 600 keys/jwt-private.pem

# Comprobar de verdad, en vez de confiar en que no hubo error.
if [ ! -s keys/jwt-private.pem ] || [ ! -s keys/jwt-public.pem ]; then
  echo "ERROR: las llaves no quedaron escritas en ./keys" >&2
  exit 1
fi
if [ "$(openssl rsa -in keys/jwt-private.pem -pubout 2>/dev/null | sha256sum)" != "$(sha256sum < keys/jwt-public.pem)" ]; then
  echo "ERROR: la llave publica no corresponde a la privada" >&2
  exit 1
fi

echo "Llaves creadas y verificadas en ./keys (no se suben a git):"
ls -l keys/jwt-private.pem keys/jwt-public.pem
