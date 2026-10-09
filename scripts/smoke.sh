#!/bin/bash
# Prueba de humo de punta a punta. Uso:
#   bash scripts/smoke.sh                       (local, http://localhost:8080)
#   BASE=https://mi-dominio bash scripts/smoke.sh
set -uo pipefail
BASE=${BASE:-http://localhost:8080}
RUN=$(date +%s)
ok=0; fallo=0
check() { if [ "$2" = "$3" ]; then echo "  OK    $1 ($2)"; ok=$((ok+1)); else echo "  FALLA $1: esperaba $3, llego $2"; fallo=$((fallo+1)); fi; }

code() { curl -s -o /tmp/smoke_body -w "%{http_code}" "$@"; }

echo "Probando $BASE"

C1=$(code -X POST "$BASE/auth/register" -H "Content-Type: application/json" \
  -d "{\"nombre\":\"Vendedor $RUN\",\"correo\":\"v$RUN@test.com\",\"password\":\"Segura123\",\"rol\":\"VENDEDOR\"}")
check "registro de vendedor" "$C1" "201"

C2=$(code -X POST "$BASE/auth/login" -H "Content-Type: application/json" \
  -d "{\"correo\":\"v$RUN@test.com\",\"password\":\"Segura123\"}")
check "login" "$C2" "200"
TOKEN=$(sed -n 's/.*"token":"\([^"]*\)".*/\1/p' /tmp/smoke_body)

C3=$(code -X POST "$BASE/api/promotions" -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" -d '{"description":"2x1 de humo","totalSlots":5}')
check "publicar promocion (token del Auth aceptado por el Core)" "$C3" "201"
ID=$(sed -n 's/.*"id":"\([^"]*\)".*/\1/p' /tmp/smoke_body)

if [ -n "${ID:-}" ]; then
  C4=$(code "$BASE/api/promotions/$ID" -H "Authorization: Bearer $TOKEN")
  check "consultar promocion" "$C4" "200"
  echo "  cupos en Redis: $(docker exec alamano-redis redis-cli GET "promotion:$ID:cupos" 2>/dev/null || echo 'no pude consultar')"
fi

C5=$(code -X POST "$BASE/api/promotions" -H "Content-Type: application/json" -d '{"description":"x","totalSlots":5}')
check "sin token da 401" "$C5" "401"

echo; echo "$ok ok, $fallo fallas"
[ "$fallo" -eq 0 ]
