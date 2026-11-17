#!/bin/bash
# Actualiza UNA VM de aplicacion (Core y Gateway). No se copia a la VM: scripts/deploy.sh
# de la VM de entrada lo ejecuta por SSH asi:  ssh azureuser@<ip-app> 'bash -s' < multivm/deploy-app.sh
# Requiere en la VM de aplicacion: ~/alamano-infra/.env, ~/alamano-infra/keys/ y Docker.
set -euo pipefail
cd "$HOME/alamano-infra"

# Mantiene el compose de la VM igual al de la rama principal. Si no se puede bajar
# (sin red, o la rama aun no lo trae) se queda con el que ya tiene.
RAW=https://raw.githubusercontent.com/ALaMano-Iluminaty/alamano-infra/main/multivm/compose.app.yml
if curl -fsS --max-time 20 "$RAW" -o multivm/compose.app.yml.nuevo < /dev/null; then
  mv multivm/compose.app.yml.nuevo multivm/compose.app.yml
else
  rm -f multivm/compose.app.yml.nuevo
  echo "(se usa el compose.app.yml que ya estaba en la VM)"
fi

COMPOSE="docker compose -f multivm/compose.app.yml --env-file .env"
$COMPOSE pull < /dev/null
# --wait no devuelve el control hasta que Core y Gateway quedan sanos (~40 s).
$COMPOSE up -d --wait --wait-timeout 180 < /dev/null
docker image prune -f < /dev/null
$COMPOSE ps < /dev/null
