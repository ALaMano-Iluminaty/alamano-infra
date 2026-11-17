#!/bin/bash
# HU-Q1: detiene una instancia de Core o de Gateway al minuto 3 de la prueba de
# disponibilidad y mide cuanto tarda el balanceador en sacarla del reparto.
#
# Terminal 1:  k6 run k6/disponibilidad.js
# Terminal 2:  bash scripts/prueba-caida.sh core-service-2        (nombre del contenedor)
#
# Debe correr en la maquina que tiene Docker con ese contenedor.
set -uo pipefail

CONTENEDOR=${1:?Uso: prueba-caida.sh <contenedor>}
ESPERA=${ESPERA:-180}
URL=${URL:-https://alamano.brazilsouth.cloudapp.azure.com/api/actuator/health}

echo ">> esperando ${ESPERA}s (minuto 3 de la prueba)"
sleep "$ESPERA"

echo ">> deteniendo $CONTENEDOR"
INICIO=$(date +%s.%N)
docker stop "$CONTENEDOR" >/dev/null

# Cuanto tarda en que una consulta ya no llegue a la instancia caida: se mide
# hasta ver respuestas 200 estables del resto.
for i in $(seq 1 60); do
    CODIGO=$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 "$URL")
    # Cualquier respuesta que no sea 5xx ni error de conexion significa que el
    # balanceador ya atiende con la instancia que sigue viva (401 sin token es valida).
    if [ "$CODIGO" != "000" ] && [ "${CODIGO:0:1}" != "5" ]; then
        FIN=$(date +%s.%N)
        printf ">> el sistema responde sin errores 5xx a los %.1f s (objetivo: 10 s o menos)\n" \
            "$(echo "$FIN - $INICIO" | bc)"
        break
    fi
    sleep 1
done

echo ">> el contenedor $CONTENEDOR sigue detenido; levantarlo al terminar:"
echo "   docker start $CONTENEDOR"
