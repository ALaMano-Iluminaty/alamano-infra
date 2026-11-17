#!/bin/bash
# Actualiza el despliegue. El CI lo ejecuta en la VM de entrada despues de publicar una imagen.
# Uso, parado en alamano-infra:  bash scripts/deploy.sh
#
# No compila: descarga las imagenes que el CI publico en GHCR.
# Tiene dos modos, segun el .env de esta VM:
#   - una sola VM (por defecto): docker-compose.yml + docker-compose.prod.yml.
#   - varias VMs: si existe multivm/compose.entrada.yml y el .env define APP1_IP y APP2_IP,
#     actualiza datos, luego app1 y app2 UNA A LA VEZ (la otra sigue atendiendo) y al final
#     la entrada. Si app1 no queda sana, no toca app2.
#     Llega a las VMs de aplicacion con la llave $APPS_SSH_KEY (por defecto ~/.ssh/deploy_apps).
set -euo pipefail
cd "$(dirname "$0")/.."

# Todo va dentro de una funcion: bash lee la funcion completa antes de ejecutarla, asi que
# el reset de abajo puede reemplazar este mismo archivo sin romper la ejecucion.
main() {
  echo ">> actualizando alamano-infra"
  git fetch --quiet origin main
  # reset en vez de pull: un pull se niega si hay archivos sin versionar que la rama ahora trae.
  # Las VMs no tienen cambios propios; .env y keys/ estan en .gitignore y no se tocan.
  git reset --hard origin/main

  if [ -f multivm/compose.entrada.yml ] && grep -qE '^APP1_IP=' .env && grep -qE '^APP2_IP=' .env; then
    despliegue_varias_vms
  else
    despliegue_una_vm
  fi
}

despliegue_una_vm() {
  local C="docker compose -f docker-compose.yml -f docker-compose.prod.yml"
  echo ">> descargando imagenes"
  $C pull

  # --wait no devuelve el control hasta que cada servicio con healthcheck quede sano.
  echo ">> levantando (esperando a que cada servicio quede sano)"
  if ! $C up -d --no-build --wait --wait-timeout 180; then
    echo "!! algun servicio no quedo sano a tiempo. Estado:"
    $C ps
    exit 1
  fi
  docker image prune -f
  $C ps
  echo "Todo sano. Prueba de humo:  BASE=https://\$DOMAIN bash scripts/smoke.sh"
}

despliegue_varias_vms() {
  local APP1_IP APP2_IP KEY USUARIO ip
  APP1_IP=$(grep -E '^APP1_IP=' .env | cut -d= -f2-)
  APP2_IP=$(grep -E '^APP2_IP=' .env | cut -d= -f2-)
  KEY=${APPS_SSH_KEY:-$HOME/.ssh/deploy_apps}
  USUARIO=${APPS_SSH_USER:-azureuser}

  echo ">> datos"
  docker compose -f multivm/compose.datos.yml --env-file .env up -d --wait --wait-timeout 180

  for ip in "$APP1_IP" "$APP2_IP"; do
    echo ">> aplicacion $ip (la otra instancia sigue atendiendo)"
    if ! ssh -i "$KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
         "$USUARIO@$ip" 'bash -s' < multivm/deploy-app.sh; then
      echo "!! $ip no quedo sana. No se toca la siguiente VM de aplicacion."
      exit 1
    fi
    sleep 5   # Caddy verifica la salud cada 2 s: que vea sana a esta antes de pasar a la otra
  done

  echo ">> entrada (Caddy, Auth, frontend, Prometheus y Grafana)"
  docker compose -f multivm/compose.entrada.yml --env-file .env pull
  if ! docker compose -f multivm/compose.entrada.yml --env-file .env up -d --wait --wait-timeout 180; then
    echo "!! la entrada no quedo sana. Estado:"
    docker compose -f multivm/compose.entrada.yml --env-file .env ps
    exit 1
  fi
  docker image prune -f
  docker compose -f multivm/compose.entrada.yml --env-file .env ps
  echo "Todo sano."
}

main "$@"
exit $?
