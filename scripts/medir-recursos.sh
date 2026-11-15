#!/bin/bash
# HU-Q6 / HU-Q10: muestreo cada 15 s de CPU y memoria por contenedor + profundidad de
# colas de RabbitMQ. La misma info esta en Grafana; este script deja un CSV portable para
# anexar al informe.
# Uso, en paralelo a cualquier prueba k6:
#   DURACION=600 bash scripts/medir-recursos.sh
set -euo pipefail

DURACION="${DURACION:-600}"      # segundos; por defecto 10 min
INTERVALO="${INTERVALO:-15}"
RABBITMQ_CONTAINER="${RABBITMQ_CONTAINER:-alamano-rabbitmq}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESULTADOS_DIR="$SCRIPT_DIR/../resultados"
mkdir -p "$RESULTADOS_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"
RECURSOS="$RESULTADOS_DIR/recursos-$STAMP.csv"
COLAS="$RESULTADOS_DIR/colas-$STAMP.csv"

echo "timestamp,container,cpu_pct,mem_usage,mem_pct,net_io,block_io" >"$RECURSOS"
echo "timestamp,cola,mensajes_listos,sin_confirmar" >"$COLAS"

echo ">> muestreando $DURACION s cada $INTERVALO s"
echo "   recursos: $RECURSOS"
echo "   colas:    $COLAS"

FIN=$(( $(date +%s) + DURACION ))
while (( $(date +%s) < FIN )); do
  T=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  # docker stats --no-stream produce una tabla de todos los contenedores.
  docker stats --no-stream \
    --format '{{.Name}},{{.CPUPerc}},{{.MemUsage}},{{.MemPerc}},{{.NetIO}},{{.BlockIO}}' \
    | sed "s|^|$T,|" >>"$RECURSOS"

  # Profundidad de cada cola (no falla si rabbitmq aun no esta listo).
  if docker exec "$RABBITMQ_CONTAINER" rabbitmqctl list_queues --quiet name messages_ready messages_unacknowledged 2>/dev/null \
      | awk -v t="$T" 'NF>=3 { printf "%s,%s,%s,%s\n", t, $1, $2, $3 }' >>"$COLAS"; then
    :
  fi

  sleep "$INTERVALO"
done

echo ">> listo. Archivos:"
echo "   $RECURSOS"
echo "   $COLAS"
