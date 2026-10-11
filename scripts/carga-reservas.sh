#!/bin/bash
# [QA AB#349] Prueba de carga de HU10: N clientes distintos intentan reservar al
# mismo tiempo el mismo vendedor disponible. Solo uno puede ganar.
#
#   bash scripts/carga-reservas.sh
#   BASE=https://mi-dominio bash scripts/carga-reservas.sh
#   CLIENTES=20 bash scripts/carga-reservas.sh                  (version corta)
#
# Reservar es POST /api/services: crea el servicio en estado RESERVED y deja al
# vendedor en BUSY. La exclusion la da un UPDATE condicional en Postgres
# (SET status='BUSY' WHERE id=? AND status='AVAILABLE'): gana el unico que ve
# rows==1. Los demas reciben 409 professional_busy.
set -uo pipefail

BASE=${BASE:-http://localhost:8080}
CLIENTES=${CLIENTES:-100}
PARALELO=${PARALELO:-$CLIENTES}
PARALELO_REGISTRO=${PARALELO_REGISTRO:-20}
LAT=${LAT:-4.6576}
LON=${LON:--74.0628}

RUN=$(date +%s)
TMP=$(mktemp -d ./.carga-reserva-XXXXXX)
trap 'rm -rf "$TMP"' EXIT

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

# El id del vendedor es el sub del token: el Core nunca lo recibe en el cuerpo.
sub_del_token() {
    local carga
    carga=$(cut -d. -f2 <<<"$1")
    while [ $(( ${#carga} % 4 )) -ne 0 ]; do carga="${carga}="; done
    printf '%s' "$carga" | tr '_-' '/+' | base64 -d 2>/dev/null \
        | sed -n 's/.*"sub":"\([^"]*\)".*/\1/p' | head -1
}

echo "== AB#349  $CLIENTES clientes reservando a la vez el mismo vendedor"
echo "   objetivo: $BASE"
echo

echo ">> 1/4  vendedor conectado y disponible"
VENDEDOR=$(credencial "vend$RUN@carga.test" VENDEDOR)
if [ -z "$VENDEDOR" ]; then
    echo "   FALLA: el Auth no entrego token de vendedor."
    exit 1
fi
PRO=$(sub_del_token "$VENDEDOR")
if [ -z "$PRO" ]; then
    echo "   FALLA: no pude sacar el sub del token del vendedor."
    exit 1
fi
ONLINE=$(curl -s -o "$TMP/online" -w '%{http_code}' -X POST "$BASE/api/professionals/me/online" \
    -H 'Content-Type: application/json' -H "Authorization: Bearer $VENDEDOR" \
    -d "{\"latitude\":$LAT,\"longitude\":$LON}")
if [ "$ONLINE" != "200" ] && [ "$ONLINE" != "201" ]; then
    echo "   FALLA: el vendedor no pudo conectarse ($ONLINE). Respuesta: $(cat "$TMP/online")"
    exit 1
fi
echo "   vendedor $PRO disponible en $LAT,$LON"

echo ">> 2/4  registrando $CLIENTES clientes (de a $PARALELO_REGISTRO)"
seq 1 "$CLIENTES" | xargs -P "$PARALELO_REGISTRO" -I{} \
    bash -c 'credencial "cli'"$RUN"'-{}@carga.test" USUARIO > "$TMP/token-{}"'
VACIOS=$(find "$TMP" -name 'token-*' -empty 2>/dev/null | wc -l)
LISTOS=$(( CLIENTES - VACIOS ))
echo "   $LISTOS tokens listos"

echo ">> 3/4  disparando las reservas con paralelismo $PARALELO"
INICIO=$(date +%s)
seq 1 "$CLIENTES" | xargs -P "$PARALELO" -I{} bash -c '
    token=$(cat "$TMP/token-{}" 2>/dev/null)
    if [ -z "$token" ]; then
        echo "sin-token" > "$TMP/code-{}"
        exit 0
    fi
    curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE/api/services" \
        -H "Content-Type: application/json" -H "Authorization: Bearer $token" \
        -d "{\"professionalId\":\"'"$PRO"'\"}" > "$TMP/code-{}"'
DURACION=$(( $(date +%s) - INICIO ))
echo "   terminaron en ${DURACION}s"

echo ">> 4/4  resultados"
CODIGOS=$(cat "$TMP"/code-* 2>/dev/null)
GANADORES=$(grep -c '^201$' <<<"$CODIGOS")
CONFLICTO=$(grep -c '^409$' <<<"$CODIGOS")
OTROS=$(grep -v -e '^201$' -e '^409$' <<<"$CODIGOS" | grep -c .)
echo "   201 (reserva ganada):  $GANADORES"
echo "   409 (vendedor ocupado): $CONFLICTO"
if [ "$OTROS" -gt 0 ]; then
    echo "   otros codigos: $(grep -v -e '^201$' -e '^409$' <<<"$CODIGOS" | sort | uniq -c | tr '\n' ' ')"
fi

# Un intento mas, ya sin carrera, para confirmar que el 409 es el correcto y no
# cualquier otro conflicto que caiga en el mismo codigo.
TARDIO=$(credencial "tarde$RUN@carga.test" USUARIO)
CUERPO=$(curl -s -X POST "$BASE/api/services" -H 'Content-Type: application/json' \
    -H "Authorization: Bearer $TARDIO" -d "{\"professionalId\":\"$PRO\"}")
echo "   el que llega tarde recibe: $CUERPO"

echo
FALLA=0
if [ "$GANADORES" -eq 1 ]; then
    echo "OK: exactamente 1 reserva entre $LISTOS intentos simultaneos."
elif [ "$GANADORES" -eq 0 ]; then
    echo "FALLA: nadie pudo reservar un vendedor que estaba disponible."
    FALLA=1
else
    echo "FALLA: $GANADORES clientes reservaron el mismo vendedor. Se rompio la exclusion."
    FALLA=1
fi
if ! grep -q 'professional_busy' <<<"$CUERPO"; then
    echo "FALLA: el rechazo no fue professional_busy."
    FALLA=1
fi
if [ "$OTROS" -gt 0 ]; then
    echo "FALLA: hubo $OTROS respuestas que no eran 201 ni 409."
    FALLA=1
fi
exit "$FALLA"
