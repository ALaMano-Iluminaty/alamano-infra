#!/usr/bin/env bash
# Genera tokens RS256 de prueba para el script de carga de ubicación en tiempo real.
# Uso: ./gen-tokens.sh [ruta-a-private.pem]
# Salida: tokens.json en el mismo directorio.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
KEY="${1:-}"

# Busca la llave en lugares habituales del proyecto
if [[ -z "$KEY" ]]; then
  for candidate in \
    "$SCRIPT_DIR/../../alamano-infra/keys/jwt-private.pem" \
    "$SCRIPT_DIR/../keys/jwt-private.pem" \
    "$SCRIPT_DIR/../../alamano-realtime-gateway/dev-keys/dev-private.pem"; do
    if [[ -f "$candidate" ]]; then
      KEY="$candidate"
      break
    fi
  done
fi

if [[ -z "$KEY" || ! -f "$KEY" ]]; then
  echo "ERROR: no se encontró la llave privada." >&2
  echo "  Pásala como argumento: $0 /ruta/a/jwt-private.pem" >&2
  echo "  O genera las llaves del proyecto primero: scripts/gen-keys.sh" >&2
  exit 1
fi

NOW="$(date +%s)"
EXP="$((NOW + 7200))"  # 2 horas

base64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

make_token() {
  local sub="$1" role="$2"
  local header='{"alg":"RS256","typ":"JWT"}'
  local payload
  payload="$(printf '{"sub":"%s","role":"%s","iat":%s,"exp":%s}' "$sub" "$role" "$NOW" "$EXP")"
  local hb pb signing sig
  hb="$(printf '%s' "$header"  | base64url)"
  pb="$(printf '%s' "$payload" | base64url)"
  signing="$hb.$pb"
  sig="$(printf '%s' "$signing" | openssl dgst -sha256 -sign "$KEY" -binary | base64url)"
  printf '%s.%s' "$signing" "$sig"
}

echo "Generando 50 tokens de barbero y 250 de cliente..." >&2

OUT="$SCRIPT_DIR/tokens.json"
printf '{\n  "barberos": [' > "$OUT"
for i in $(seq 1 50); do
  token="$(make_token "barbero-$i" "PROFESSIONAL")"
  [[ $i -gt 1 ]] && printf ',' >> "$OUT"
  printf '"%s"' "$token" >> "$OUT"
done
printf '],\n  "clientes": [' >> "$OUT"
for i in $(seq 1 250); do
  token="$(make_token "cliente-$i" "CLIENT")"
  [[ $i -gt 1 ]] && printf ',' >> "$OUT"
  printf '"%s"' "$token" >> "$OUT"
done
printf ']\n}\n' >> "$OUT"

echo "Tokens escritos en $OUT" >&2
