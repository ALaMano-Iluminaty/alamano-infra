#!/bin/bash
# Genera el par RS256 en ./keys, en formato PKCS#8, que es el que leen los servicios.
set -euo pipefail
cd "$(dirname "$0")/.."

IMAGEN_AUTH=ghcr.io/alamano-iluminaty/alamano-auth-service:latest

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

chmod 644 keys/jwt-public.pem    # la leen Core y el Gateway
chmod 600 keys/jwt-private.pem   # solo la lee Auth

# Comprobar de verdad, en vez de confiar en que no hubo error.
if [ ! -s keys/jwt-private.pem ] || [ ! -s keys/jwt-public.pem ]; then
  echo "ERROR: las llaves no quedaron escritas en ./keys" >&2
  exit 1
fi
if [ "$(openssl rsa -in keys/jwt-private.pem -pubout 2>/dev/null | sha256sum)" != "$(sha256sum < keys/jwt-public.pem)" ]; then
  echo "ERROR: la llave publica no corresponde a la privada" >&2
  exit 1
fi

# En Linux, el contenedor de Auth corre como el usuario 'app', no como el tuyo.
# Con la privada en 600 y de tu propiedad, el contenedor NO puede leerla y muere
# al arrancar con AccessDeniedException. Se le da la propiedad al usuario del
# contenedor en vez de abrir el archivo a todo el mundo.
# (En Docker Desktop sobre Windows o macOS esto no hace falta: el montaje ignora
# los permisos de Unix. Por eso el fallo solo aparece al desplegar.)
if [ "$(uname -s)" = "Linux" ] && command -v docker >/dev/null 2>&1; then
  if APPUID=$(docker run --rm --entrypoint id "$IMAGEN_AUTH" -u 2>/dev/null); then
    if [ "$APPUID" != "$(id -u)" ]; then
      if chown "$APPUID" keys/jwt-private.pem 2>/dev/null || sudo chown "$APPUID" keys/jwt-private.pem; then
        echo "Llave privada asignada al uid $APPUID, que es con el que corre el contenedor."
      else
        echo "AVISO: no pude cambiar el dueño de keys/jwt-private.pem." >&2
        echo "  Auth va a fallar con AccessDeniedException. Corre a mano:" >&2
        echo "    sudo chown $APPUID keys/jwt-private.pem" >&2
      fi
    fi
  else
    echo "AVISO: no pude averiguar con que usuario corre $IMAGEN_AUTH." >&2
    echo "  Si Auth falla con AccessDeniedException sobre /keys/jwt-private.pem, corre:" >&2
    echo "    APPUID=\$(docker run --rm --entrypoint id $IMAGEN_AUTH -u)" >&2
    echo "    sudo chown \$APPUID keys/jwt-private.pem" >&2
  fi
fi

echo "Llaves creadas y verificadas en ./keys (no se suben a git):"
ls -l keys/jwt-private.pem keys/jwt-public.pem
