#!/bin/bash
# [QA AB#353] Prueba de carga de HU11: N clientes distintos reclaman a la vez una
# promocion con M cupos. El sistema puede entregar menos de M si algo falla, pero
# NUNCA mas de M: ese es el invariante que esta prueba vigila.
#
#   bash scripts/carga-promociones.sh
#   BASE=https://mi-dominio bash scripts/carga-promociones.sh
#   CLIENTES=50 CUPOS=10 bash scripts/carga-promociones.sh      (version corta)
#
# Por que clientes DISTINTOS: el Core guarda cada reclamo en promotion_claims con
# insertIfNew, o sea un cupo por cliente. Con 300 hilos usando el mismo token el
# primero toma el cupo y los otros 299 reciben 409 por repetido, no por falta de
# cupos: la prueba daria verde sin haber probado nada de concurrencia.
set -uo pipefail

BASE=${BASE:-http://localhost:8080}
CLIENTES=${CLIENTES:-300}
CUPOS=${CUPOS:-50}
# Cuantos reclamos se disparan a la vez. Por defecto todos.
PARALELO=${PARALELO:-$CLIENTES}
# Los registros van de a pocos: cada uno cuesta un BCrypt y el Auth es el cuello
# de botella del montaje, no de lo que queremos medir.
PARALELO_REGISTRO=${PARALELO_REGISTRO:-20}

RUN=$(date +%s)
# Relativo a proposito: Git Bash en Windows traduce /tmp y el curl nativo no lo encuentra.
TMP=$(mktemp -d ./.carga-promo-XXXXXX)
trap 'rm -rf "$TMP"' EXIT

campo() { sed -n "s/.*\"$2\":\"\([^\"]*\)\".*/\1/p" <<<"$1" | head -1; }

# Registra (o reusa) un usuario y deja su token en stdout.
credencial() {
    local correo=$1 rol=$2 cuerpo token
    cuerpo=$(curl -s -X POST "$BASE/auth/register" -H 'Content-Type: application/json' \
        -d "{\"nombre\":\"Carga $correo\",\"correo\":\"$correo\",\"password\":\"Segura123\",\"rol\":\"$rol\"}")
    token=$(sed -n 's/.*"token":"\([^"]*\)".*/\1/p' <<<"$cuerpo" | head -1)
    if [ -z "$token" ]; then
        cuerpo=$(curl -s -X POST "$BASE/auth/login" -H 'Content-Type: application/json' \
            -d "{\"correo\":\"$correo\",\"password\":\"Segura123\"}")
        token=$(sed -n 's/.*"token":"\([^"]*\)".*/\1/p' <<<"$cuerpo" | head -1)
    fi
    printf '%s' "$token"
}
export -f credencial
export BASE TMP

echo "== AB#353  $CLIENTES clientes contra una promocion de $CUPOS cupos"
echo "   objetivo: $BASE"
echo

echo ">> 1/4  vendedor y promocion"
VENDEDOR=$(credencial "vend$RUN@carga.test" VENDEDOR)
if [ -z "$VENDEDOR" ]; then
    echo "   FALLA: el Auth no entrego token de vendedor. Esta arriba $BASE/auth ?"
    exit 1
fi
PROMO_JSON=$(curl -s -X POST "$BASE/api/promotions" -H 'Content-Type: application/json' \
    -H "Authorization: Bearer $VENDEDOR" \
    -d "{\"description\":\"Carga $RUN\",\"totalSlots\":$CUPOS}")
PROMO=$(campo "$PROMO_JSON" id)
if [ -z "$PROMO" ]; then
    echo "   FALLA: no se pudo publicar la promocion. Respuesta: $PROMO_JSON"
    exit 1
fi
echo "   promocion $PROMO con $CUPOS cupos"

echo ">> 2/4  registrando $CLIENTES clientes (de a $PARALELO_REGISTRO)"
seq 1 "$CLIENTES" | xargs -P "$PARALELO_REGISTRO" -I{} \
    bash -c 'credencial "cli'"$RUN"'-{}@carga.test" USUARIO > "$TMP/token-{}"'
VACIOS=$(find "$TMP" -name 'token-*' -empty 2>/dev/null | wc -l)
LISTOS=$(( CLIENTES - VACIOS ))
echo "   $LISTOS tokens listos"
if [ "$VACIOS" -gt 0 ]; then
    echo "   OJO: $VACIOS clientes se quedaron sin token y no van a reclamar."
fi

echo ">> 3/4  disparando los reclamos con paralelismo $PARALELO"
INICIO=$(date +%s)
seq 1 "$CLIENTES" | xargs -P "$PARALELO" -I{} bash -c '
    token=$(cat "$TMP/token-{}" 2>/dev/null)
    if [ -z "$token" ]; then
        echo "sin-token" > "$TMP/code-{}"
        exit 0
    fi
    curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE/api/promotions/'"$PROMO"'/claim" \
        -H "Authorization: Bearer $token" > "$TMP/code-{}"'
DURACION=$(( $(date +%s) - INICIO ))
echo "   terminaron en ${DURACION}s"

echo ">> 4/4  resultados"
CODIGOS=$(cat "$TMP"/code-* 2>/dev/null)
OK=$(grep -c '^200$' <<<"$CODIGOS")
CONFLICTO=$(grep -c '^409$' <<<"$CODIGOS")
OTROS=$(grep -v -e '^200$' -e '^409$' <<<"$CODIGOS" | grep -c . )
echo "   200 (cupo entregado):      $OK"
echo "   409 (sin cupo o repetido): $CONFLICTO"
if [ "$OTROS" -gt 0 ]; then
    echo "   otros codigos: $(grep -v -e '^200$' -e '^409$' <<<"$CODIGOS" | sort | uniq -c | tr '\n' ' ')"
fi

QUEDAN=$(curl -s "$BASE/api/promotions/$PROMO" -H "Authorization: Bearer $VENDEDOR" \
    | sed -n 's/.*"availableSlots":\([0-9-]*\).*/\1/p' | head -1)
echo "   cupos que reporta el Core: ${QUEDAN:-no se pudo leer}"

# Solo cuando se corre dentro de la VM: confirma que el contador real quedo en 0
# y que hay exactamente un claim guardado por cada cupo entregado.
if command -v docker >/dev/null 2>&1 && docker ps --format '{{.Names}}' 2>/dev/null | grep -q alamano-redis; then
    echo "   contador en Redis: $(docker exec alamano-redis redis-cli GET "promotion:$PROMO:cupos" 2>/dev/null)"
    FILAS=$(docker exec alamano-postgres psql -U "${CORE_DB_USER:-core_app}" -d alamano -t -A \
        -c "SELECT count(*) FROM core.promotion_claims WHERE promotion_id = '$PROMO'" 2>/dev/null | tr -d ' ')
    [ -n "$FILAS" ] && echo "   filas en promotion_claims: $FILAS"
fi

echo
FALLA=0
if [ "$OK" -gt "$CUPOS" ]; then
    echo "FALLA: se entregaron $OK cupos de $CUPOS. Hubo sobreventa."
    FALLA=1
elif [ "$OK" -lt "$CUPOS" ]; then
    echo "FALLA: solo se entregaron $OK de los $CUPOS cupos disponibles."
    FALLA=1
else
    echo "OK: exactamente $CUPOS cupos entre $LISTOS solicitudes simultaneas."
fi
if [ "$OTROS" -gt 0 ]; then
    echo "FALLA: hubo $OTROS respuestas que no eran 200 ni 409."
    FALLA=1
fi
exit "$FALLA"
