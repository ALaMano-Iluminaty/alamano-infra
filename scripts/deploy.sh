#!/bin/bash
# Actualiza los repos y reconstruye lo que cambio.
# Uso, parado en alamano-infra:  bash scripts/deploy.sh
set -euo pipefail
cd "$(dirname "$0")/.."

for repo in alamano-auth-service alamano-core-service alamano-realtime-gateway alamano-frontend; do
  if [ -d "../$repo/.git" ]; then
    echo ">> git pull $repo"
    git -C "../$repo" pull --ff-only
  else
    echo ">> $repo no esta clonado, se omite"
  fi
done
git pull --ff-only

docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --build
docker image prune -f
docker compose ps
