# Resultados de rendimiento (Sprint 2)

Plantilla para registrar cada corrida. El objetivo es que cualquiera pueda
reproducir la medicion con los scripts de este repo.

## Topologia usada
- Entorno: una sola VM (B2s) / 4 VMs (anotar)
- Stack: `docker-compose.yml` + `docker-compose.prod.yml` + `docker-compose.ha.yml` +
  `docker-compose.observabilidad.yml`
- Instancias: 2 Core, 2 Gateway, 1 Auth, 1 Nginx, 1 Caddy, 1 Postgres, 1 Redis,
  1 RabbitMQ.

## Como registrar una corrida
1. Corre la prueba correspondiente (ver tablas de abajo).
2. Pega el resumen del log en la fila "Resultado".
3. Adjunta tambien la captura del tablero Grafana en el mismo rango horario.
4. Marca si cumple el AC.

## HU-Q1 — Disponibilidad con una instancia caida
- Script: `bash scripts/prueba-disponibilidad.sh`
- AC: Caddy detecta la caida en <= 10 s, exito >= 99 %, reconexion WS <= 30 s.

| Fecha | Corrida | p95 HTTP | Errores HTTP | Reconex WS p95 | Cumple |
|-------|---------|----------|--------------|----------------|--------|
|       |         |          |              |                |        |

## HU-Q6 — 50 barberos + 250 clientes en WS, 10 min
- Script: `bash k6/run.sh wss://$DOMAIN/ws`
- Paralelo: `DURACION=600 bash scripts/medir-recursos.sh`
- AC: p95 latencia ubicacion < 500 ms, CPU por nodo < 80 %, colas no crecen sostenido.

| Fecha | p95 roundtrip | Max CPU Core | Max CPU Gateway | Cola max | Cumple |
|-------|---------------|--------------|-----------------|----------|--------|
|       |               |              |                 |          |        |

## HU-Q7 / HU-Q8 — Cargas de reserva y promocion contra HA
- Script: `bash scripts/correr-ha.sh`
- AC HU-Q7: p95 <= 300 ms, sin 5xx, exactamente 1 reserva por slot.
- AC HU-Q8: 50 clientes por ronda reciben la promocion.

| Fecha | HU | p95 | 5xx | Resultado logico | Cumple |
|-------|----|-----|-----|------------------|--------|
|       |    |     |     |                  |        |

## HU-Q9 — 250 clientes consultando barberos cercanos, 10 min
- Script: `bash scripts/prueba-cercanos.sh`
- AC: p95 <= 300 ms, errores < 1 %, cache >= 80 %.

| Fecha | p95 | Errores | % cache | Cumple |
|-------|-----|---------|---------|--------|
|       |     |         |         |        |
