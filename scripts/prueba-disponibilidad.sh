#!/bin/bash
# HU-Q1: 200 usuarios activos, al minuto 3 se tumba una instancia (y a los 5 min vuelve).
# El escenario se levanta con docker-compose.ha.yml (2 Core + 2 Gateway tras Caddy).
# Uso, parado en alamano-infra:
#   BASE=https://alamano.example.com bash scripts/prueba-disponibilidad.sh
set -euo pipefail

BASE="${BASE:-http://localhost}"
VICTIMA="${VICTIMA:-alamano-core-service-2}"   # tambien sirve alamano-realtime-gateway-2

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESULTADOS_DIR="$SCRIPT_DIR/../resultados"
mkdir -p "$RESULTADOS_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"

# Tokens para los 250 clientes (se reusa el generador existente).
if [[ ! -f "$SCRIPT_DIR/../k6/tokens.json" ]]; then
  echo ">> generando tokens"
  node "$SCRIPT_DIR/../k6/gen-tokens.js"
fi

echo ">> arranco k6 (5 min) en segundo plano. Resultados: $RESULTADOS_DIR/disponibilidad-$STAMP.json"
k6 run \
  --env BASE="$BASE" \
  --out json="$RESULTADOS_DIR/disponibilidad-$STAMP.json" \
  "$SCRIPT_DIR/../k6/disponibilidad.js" \
  >"$RESULTADOS_DIR/disponibilidad-$STAMP.log" 2>&1 &
K6_PID=$!

echo ">> espero 3 min antes de tumbar $VICTIMA"
sleep 180
echo ">> deteniendo $VICTIMA ($(date +%H:%M:%S))"
docker stop "$VICTIMA"

echo ">> 2 min con la instancia caida; Caddy debe seguir repartiendo a la otra"
sleep 120
echo ">> reiniciando $VICTIMA ($(date +%H:%M:%S))"
docker start "$VICTIMA"

echo ">> espero a k6..."
wait "$K6_PID" || true

echo
echo "==> umbrales del escenario (resumen al final del log):"
tail -40 "$RESULTADOS_DIR/disponibilidad-$STAMP.log" | grep -E "http_errors|http_latency_ms|ws_reconnect_gap_s|checks" || true
echo
echo "Resultados completos:"
echo "  $RESULTADOS_DIR/disponibilidad-$STAMP.json"
echo "  $RESULTADOS_DIR/disponibilidad-$STAMP.log"
