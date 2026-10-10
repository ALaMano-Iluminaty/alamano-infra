#!/bin/bash
# Prueba de humo de punta a punta. Uso:
#   bash scripts/smoke.sh                       (local, http://localhost:8080)
#   BASE=https://mi-dominio bash scripts/smoke.sh
set -uo pipefail
BASE=${BASE:-http://localhost:8080}
RUN=$(date +%s)
ok=0; fallo=0
check() { if [ "$2" = "$3" ]; then echo "  OK    $1 ($2)"; ok=$((ok+1)); else echo "  FALLA $1: esperaba $3, llego $2"; fallo=$((fallo+1)); fi; }

BODY=./.smoke_body
trap 'rm -f "$BODY"' EXIT
code() { curl -s -o "$BODY" -w "%{http_code}" "$@"; }

echo "Probando $BASE"

C1=$(code -X POST "$BASE/auth/register" -H "Content-Type: application/json" \
  -d "{\"nombre\":\"Vendedor $RUN\",\"correo\":\"v$RUN@test.com\",\"password\":\"Segura123\",\"rol\":\"VENDEDOR\"}")
check "registro de vendedor" "$C1" "201"

C2=$(code -X POST "$BASE/auth/login" -H "Content-Type: application/json" \
  -d "{\"correo\":\"v$RUN@test.com\",\"password\":\"Segura123\"}")
check "login" "$C2" "200"
TOKEN=$(sed -n 's/.*"token":"\([^"]*\)".*/\1/p' "$BODY")

C3=$(code -X POST "$BASE/api/promotions" -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" -d '{"description":"2x1 de humo","totalSlots":5}')
check "publicar promocion (token del Auth aceptado por el Core)" "$C3" "201"
ID=$(sed -n 's/.*"id":"\([^"]*\)".*/\1/p' "$BODY")

if [ -n "${ID:-}" ]; then
  C4=$(code "$BASE/api/promotions/$ID" -H "Authorization: Bearer $TOKEN")
  check "consultar promocion" "$C4" "200"
  echo "  cupos en Redis: $(docker exec alamano-redis redis-cli GET "promotion:$ID:cupos" 2>/dev/null || echo 'no pude consultar')"
fi

C5=$(code -X POST "$BASE/api/promotions" -H "Content-Type: application/json" -d '{"description":"x","totalSlots":5}')
check "sin token da 401" "$C5" "401"

# El frontend: nginx le pasa "/" tal cual y el index.html trae el div de React.
C6=$(code "$BASE/")
check "frontend responde en /" "$C6" "200"
if grep -q 'id="root"' "$BODY" 2>/dev/null; then
  echo "  OK    el index.html es el de la SPA"; ok=$((ok+1))
else
  echo "  FALLA / responde pero no parece el index de la SPA"; fallo=$((fallo+1))
fi

# El Gateway: handshake de WebSocket. 101 = cambio de protocolo aceptado.
# El token no va aqui, va en el CONNECT de STOMP, asi que esto pasa sin login.
# La cabecera Origin tiene que estar en ALLOWED_ORIGINS del Gateway.
WS=$(curl -s -i --http1.1 --max-time 8 \
  -H "Connection: Upgrade" -H "Upgrade: websocket" \
  -H "Sec-WebSocket-Version: 13" -H "Sec-WebSocket-Key: ZGVtbyBkZSBodW1vIDEyMw==" \
  -H "Origin: $BASE" "$BASE/ws" 2>/dev/null | head -n 1 | tr -d '\r')
case "$WS" in
  *101*) check "handshake del WebSocket en /ws" "101" "101" ;;
  *)     check "handshake del WebSocket en /ws" "${WS:-sin respuesta}" "101" ;;
esac

echo; echo "$ok ok, $fallo fallas"
[ "$fallo" -eq 0 ]
