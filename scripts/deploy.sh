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

# --wait no devuelve el control hasta que cada servicio con healthcheck quede
# sano. Sin esto el script termina en segundos, los dos servicios Java todavia
# estan arrancando (tardan ~40s) y cualquier prueba que corras detras da 502.
echo ">> levantando (esperando a que cada servicio quede sano)"
if ! docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --no-build --wait --wait-timeout 180; then
  echo
  echo "!! algun servicio no quedo sano a tiempo. Estado:"
  docker compose -f docker-compose.yml -f docker-compose.prod.yml ps
  echo "Mira los logs del que no arranco: docker logs <nombre del contenedor>"
  exit 1
fi

docker image prune -f
docker compose -f docker-compose.yml -f docker-compose.prod.yml ps

echo
echo "Todo sano. Prueba de humo:"
echo "  BASE=https://\$DOMAIN bash scripts/smoke.sh"
