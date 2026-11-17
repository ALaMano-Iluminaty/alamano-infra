#!/usr/bin/env bash
# HU-Q3 / HU-Q5 (AB#385, AB#387, AB#389): prueba automatica de accesos y validacion de entradas contra el Core.
# Uso, desde la raiz del repo alamano-infra en la VM de entrada (necesita k6/tokens.json):
#   BASE=https://alamano.brazilsouth.cloudapp.azure.com bash scripts/prueba-accesos.sh
# Sale con codigo 1 si alguna comprobacion falla. No escribe datos: solo peticiones rechazadas o de lectura.
set -u
BASE="${BASE:-https://alamano.brazilsouth.cloudapp.azure.com}"
TOKENS="${TOKENS:-k6/tokens.json}"
[ -f "$TOKENS" ] || { echo "No existe $TOKENS: corre 'sudo bash k6/gen-tokens.sh' primero."; exit 2; }

token() { python3 -c "import json,sys;print(json.load(open('$TOKENS'))['$1'][$2])"; }
BARBERO=$(token barberos 10)   # barbero-11
CLIENTE=$(token clientes 0)    # cliente-1
CLIENTE2=$(token clientes 1)   # cliente-2

OK=0; FAIL=0
req() { # metodo ruta token [cuerpo]  -> imprime el codigo HTTP
  local metodo="$1" ruta="$2" tok="$3" cuerpo="${4:-}"
  local args=(-s -o /tmp/prueba-accesos.body -w '%{http_code}' -X "$metodo" "$BASE$ruta")
  [ -n "$tok" ] && args+=(-H "Authorization: Bearer $tok")
  [ -n "$cuerpo" ] && args+=(-H 'Content-Type: application/json' -d "$cuerpo")
  curl "${args[@]}"
}
check() { # nombre esperado obtenido
  if [ "$2" = "$3" ]; then OK=$((OK+1)); printf '  PASS  %-62s esperado=%s obtenido=%s\n' "$1" "$2" "$3"
  else FAIL=$((FAIL+1)); printf '  FAIL  %-62s esperado=%s obtenido=%s\n' "$1" "$2" "$3"; fi
}

echo "== Autenticacion"
check "Sin token: GET /api/professionals/nearby" 401 "$(req GET '/api/professionals/nearby?lat=4.61&lng=-74.1' '')"
check "Token basura: GET /api/professionals/nearby" 401 "$(req GET '/api/professionals/nearby?lat=4.61&lng=-74.1' 'abc.def.ghi')"

echo "== Roles (403)"
check "CLIENT no publica promociones (POST /api/promotions)" 403 "$(req POST /api/promotions "$CLIENTE" '{"description":"x","totalSlots":5}')"
check "CLIENT no se conecta (POST /api/professionals/me/online)" 403 "$(req POST /api/professionals/me/online "$CLIENTE" '{"latitude":4.6,"longitude":-74.1}')"
check "CLIENT no reporta ubicacion (POST /api/services/{id}/location)" 403 "$(req POST /api/services/00000000-0000-0000-0000-000000000000/location "$CLIENTE" '{"lat":4.6,"lng":-74.1}')"
check "CLIENT no lista sus promociones (GET /api/promotions/mine)" 403 "$(req GET /api/promotions/mine "$CLIENTE")"

echo "== Dueno del recurso (403)"
req GET /api/services/active "$BARBERO" >/dev/null
SERVICIO=$(python3 -c "import json;d=json.load(open('/tmp/prueba-accesos.body'));print(d[0]['id'] if d else '')" 2>/dev/null)
if [ -z "$SERVICIO" ]; then
  echo "  (omitido: barbero-11 no tiene servicio activo; corre antes la preparacion de barberos de la prueba en tiempo real)"
else
  check "Participante lee su servicio (GET /api/services/{id})" 200 "$(req GET "/api/services/$SERVICIO" "$BARBERO")"
  check "Ajeno NO lee el servicio (GET /api/services/{id})" 403 "$(req GET "/api/services/$SERVICIO" "$CLIENTE2")"
  check "Ajeno NO cambia el estado (PATCH /api/services/{id}/status)" 403 "$(req PATCH "/api/services/$SERVICIO/status" "$CLIENTE2" '{"status":"CANCELLED"}')"
fi
check "Servicio inexistente (GET /api/services/{id})" 404 "$(req GET /api/services/00000000-0000-0000-0000-000000000000 "$CLIENTE")"

echo "== Validacion de entradas (400)"
check "lat no numerica" 400 "$(req GET '/api/professionals/nearby?lat=abc&lng=-74.1' "$CLIENTE")"
check "lat fuera de rango (999)" 400 "$(req GET '/api/professionals/nearby?lat=999&lng=-74.1' "$CLIENTE")"
check "radio negativo" 400 "$(req GET '/api/professionals/nearby?lat=4.61&lng=-74.1&radiusKm=-1' "$CLIENTE")"
check "radio mayor al maximo (500 km)" 400 "$(req GET '/api/professionals/nearby?lat=4.61&lng=-74.1&radiusKm=500' "$CLIENTE")"
check "inyeccion SQL en lat" 400 "$(req GET "/api/professionals/nearby?lat=1%3BDROP%20TABLE%20professionals&lng=-74.1" "$CLIENTE")"
check "promocion con descripcion de 501 caracteres" 400 "$(req POST /api/promotions "$BARBERO" "{\"description\":\"$(printf 'a%.0s' $(seq 1 501))\",\"totalSlots\":5}")"
check "promocion con 0 cupos" 400 "$(req POST /api/promotions "$BARBERO" '{"description":"x","totalSlots":0}')"
check "promocion con 99999 cupos" 400 "$(req POST /api/promotions "$BARBERO" '{"description":"x","totalSlots":99999}')"
check "estado de servicio inventado" 400 "$(req PATCH /api/services/00000000-0000-0000-0000-000000000000/status "$CLIENTE" '{"status":"HACK"}')"
check "cuerpo que no es JSON" 400 "$(req POST /api/services "$CLIENTE" '{esto no es json')"
check "identificador de vendedor de 65 caracteres" 400 "$(req POST /api/services "$CLIENTE" "{\"professionalId\":\"$(printf 'x%.0s' $(seq 1 65))\"}")"
check "texto SQL como vendedor: 409, nunca 500" 409 "$(req POST /api/services "$CLIENTE" "{\"professionalId\":\"x'; DROP TABLE services;--\"}")"

echo
echo "Resultado: $OK correctas, $FAIL fallidas."
[ "$FAIL" -eq 0 ]
