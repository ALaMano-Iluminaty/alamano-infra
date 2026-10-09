#!/bin/bash
# Actualiza el despliegue de la VM.
# Uso, parado en alamano-infra:  bash scripts/deploy.sh
#
# No compila: descarga las imagenes que el CI publico en GHCR al mergear a la
# rama principal. Por eso la VM no necesita los repos de los servicios.
set -euo pipefail
cd "$(dirname "$0")/.."

echo ">> actualizando alamano-infra"
git pull --ff-only

echo ">> descargando imagenes"
docker compose -f docker-compose.yml -f docker-compose.prod.yml pull

echo ">> levantando"
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --no-build

docker image prune -f
docker compose -f docker-compose.yml -f docker-compose.prod.yml ps
