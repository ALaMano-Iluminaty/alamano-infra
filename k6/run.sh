#!/usr/bin/env bash
# Ejecuta la prueba de carga de ubicación en tiempo real (HU-Q6).
# Uso: ./run.sh [GATEWAY_URL] [ruta-a-private.pem]
#   GATEWAY_URL   ws://host:8083/ws   (default: ws://localhost:8083/ws)
#   private.pem   ruta a la llave para gen-tokens.sh (opcional si ya existe tokens.json)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GATEWAY_URL="${1:-ws://localhost:8083/ws}"
PRIVATE_KEY="${2:-}"

if ! command -v k6 >/dev/null 2>&1; then
  echo "ERROR: k6 no está instalado." >&2
  echo "  Instalación: https://k6.io/docs/get-started/installation/" >&2
  exit 1
fi

# Genera tokens si no existen o si se pasó una llave explícita
if [[ ! -f "$SCRIPT_DIR/tokens.json" || -n "$PRIVATE_KEY" ]]; then
  echo "Generando tokens de prueba..."
  node "$SCRIPT_DIR/gen-tokens.js" ${PRIVATE_KEY:+"$PRIVATE_KEY"}
fi

echo "Iniciando prueba contra $GATEWAY_URL"
echo "  50 barberos · 250 clientes · 10 min"
echo ""

k6 run \
  --env GATEWAY_URL="$GATEWAY_URL" \
  --out json="$SCRIPT_DIR/results.json" \
  "$SCRIPT_DIR/ubicacion-realtime.js"
