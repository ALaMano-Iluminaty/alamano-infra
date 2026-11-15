#!/bin/bash
# HU-Q7 y HU-Q8: correr las cargas existentes (reservas y promociones) contra el stack HA
# (2 Core + 2 Gateway tras Caddy) y guardar el resultado para el informe.
# Uso, parado en alamano-infra:
#   BASE=https://alamano.example.com bash scripts/correr-ha.sh
set -euo pipefail

BASE="${BASE:-http://localhost}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESULTADOS_DIR="$SCRIPT_DIR/../resultados"
mkdir -p "$RESULTADOS_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"

echo ">> midiendo recursos en segundo plano"
DURACION=600 bash "$SCRIPT_DIR/medir-recursos.sh" >"$RESULTADOS_DIR/recursos-$STAMP.log" 2>&1 &
RECURSOS_PID=$!

echo ">> HU-Q7: carga de reservas (p95 <= 300 ms, 1 reserva por slot)"
BASE="$BASE" bash "$SCRIPT_DIR/carga-reservas.sh" | tee "$RESULTADOS_DIR/reservas-$STAMP.log"

echo ">> HU-Q8: carga de promociones (50 clientes por ronda)"
BASE="$BASE" bash "$SCRIPT_DIR/carga-promociones.sh" | tee "$RESULTADOS_DIR/promociones-$STAMP.log"

kill "$RECURSOS_PID" 2>/dev/null || true
echo
echo "Resultados escritos en $RESULTADOS_DIR (stamp $STAMP). Anotarlos en docs/resultados-rendimiento.md"
