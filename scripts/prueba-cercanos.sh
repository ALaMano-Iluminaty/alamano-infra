#!/bin/bash
# HU-Q9: 250 clientes cada 5 s durante 10 min. Ademas del k6, mide la razon de cache de
# Redis (keyspace_hits / keyspace_misses) comparando antes y despues del test.
# Uso, parado en alamano-infra:
#   BASE=https://alamano.example.com bash scripts/prueba-cercanos.sh
set -euo pipefail

BASE="${BASE:-http://localhost}"
REDIS_CONTAINER="${REDIS_CONTAINER:-alamano-redis}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESULTADOS_DIR="$SCRIPT_DIR/../resultados"
mkdir -p "$RESULTADOS_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"

if [[ ! -f "$SCRIPT_DIR/../k6/tokens.json" ]]; then
  echo ">> generando tokens (la llave privada es de root: pide sudo)"
  sudo bash "$SCRIPT_DIR/../k6/gen-tokens.sh"
fi

# Hits/misses iniciales. "INFO stats" devuelve un bloque; filtramos lo que importa.
leer_stats() {
  docker exec "$REDIS_CONTAINER" redis-cli INFO stats | tr -d '\r' \
    | awk -F: '/^keyspace_hits:/ {print $2} /^keyspace_misses:/ {print $2}'
}
echo ">> leyendo Redis antes del test"
mapfile -t ANTES < <(leer_stats)
HITS_ANTES=${ANTES[0]:-0}
MISSES_ANTES=${ANTES[1]:-0}
echo "    hits=$HITS_ANTES  misses=$MISSES_ANTES"

echo ">> corriendo k6 (10 min)"
if command -v k6 >/dev/null 2>&1; then
  k6 run \
    --env BASE="$BASE" \
    --out json="$RESULTADOS_DIR/cercanos-$STAMP.json" \
    "$SCRIPT_DIR/../k6/barberos-cercanos.js" \
    | tee "$RESULTADOS_DIR/cercanos-$STAMP.log"
else
  # Las VMs no traen k6: se usa la imagen oficial (el resumen queda en el .log).
  docker run --rm -i --network host -v "$SCRIPT_DIR/../k6:/k6:ro" -w /k6 \
    -e BASE="$BASE" grafana/k6 run barberos-cercanos.js \
    | tee "$RESULTADOS_DIR/cercanos-$STAMP.log"
fi

echo ">> leyendo Redis despues del test"
mapfile -t DESPUES < <(leer_stats)
HITS_DESPUES=${DESPUES[0]:-0}
MISSES_DESPUES=${DESPUES[1]:-0}

HITS=$((HITS_DESPUES - HITS_ANTES))
MISSES=$((MISSES_DESPUES - MISSES_ANTES))
TOTAL=$((HITS + MISSES))
if (( TOTAL > 0 )); then
  RAZON=$(awk -v h="$HITS" -v t="$TOTAL" 'BEGIN { printf "%.2f", (h/t)*100 }')
else
  RAZON="N/A"
fi

{
  echo "Prueba HU-Q9 $STAMP"
  echo "  hits durante el test:   $HITS"
  echo "  misses durante el test: $MISSES"
  echo "  razon cache (hits/total): ${RAZON}%  (AC: >= 80%)"
} | tee "$RESULTADOS_DIR/cercanos-$STAMP.cache.txt"
