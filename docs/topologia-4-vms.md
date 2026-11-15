# Topologia de 4 VMs (HU-Q1)

Diagrama fisico del despliegue: 1 VM de entrada, 2 de aplicacion y 1 de datos. El
balanceo entre las dos VMs de aplicacion lo hace Caddy (ver `caddy/Caddyfile.ha`).

```
                    Internet
                       |
                       v
         +----------------------------+
         |  VM entrada  (B2s, publica)|
         |  - Caddy (80/443) + ratelimit
         |  - Prometheus, Grafana
         |  - nginx (opcional)
         +--+----------------------+--+
            |                      |
   /auth,/api                  /ws
            v                      v
  +-------------------+  +-------------------+
  |  VM app-1 (B2s)   |  |  VM app-2 (B2s)   |
  |  - auth-service   |  |  - auth-service   |
  |  - core-service   |  |  - core-service   |
  |  - realtime-gw    |  |  - realtime-gw    |
  |  - node-exporter  |  |  - node-exporter  |
  |  - cadvisor       |  |  - cadvisor       |
  +---------+---------+  +---------+---------+
            \                      /
             \                    /
              v                  v
            +----------------------+
            |  VM datos (B2s)      |
            |  - postgres          |
            |  - redis             |
            |  - rabbitmq (+prom)  |
            |  - node-exporter     |
            +----------------------+
```

- Solo la VM de entrada abre 80/443 al mundo. Las otras tres se conectan por la
  red privada de Azure (NSG permite entre ellas, nada mas).
- Prometheus corre en la VM de entrada y "raspa" por IP privada los `/actuator/
  prometheus` de las dos VMs de app y los exporters de la VM de datos.
- Caddy aplica el `rate_limit` por IP antes del reparto, asi las dos VMs de app
  nunca ven mas de 100 req/min/IP.

## Variables de entorno en la VM de entrada
`.env` en la VM de entrada:

```
DOMAIN=alamano.<zona>.cloudapp.azure.com
CORE_UPSTREAMS=10.0.1.4:8082 10.0.1.5:8082
GATEWAY_UPSTREAMS=10.0.1.4:8083 10.0.1.5:8083
AUTH_UPSTREAMS=10.0.1.4:8081 10.0.1.5:8081
```

En Prometheus (`prometheus/prometheus.yml`) reemplazar los `targets` de auth, core
y gateway por `10.0.1.4:808X` y `10.0.1.5:808X`.

## Aprovisionamiento con Azure CLI
Ver `scripts/provision-azure.sh`: crea el grupo de recursos, la VNet, un unico
NSG con 22 (restringido a tu IP), 80 y 443 para la VM de entrada, otro NSG
"interno" para las tres restantes, y las 4 VMs B2s con Ubuntu 22.04. Al final
imprime las IPs publica/privada de cada maquina.

## Que corre cada VM
Cada subcarpeta de `vm/` trae el `docker-compose` especifico (los servicios que
corresponden) y un `.env.example` propio.
- `vm/entrada/`: Caddy + Prometheus + Grafana (+ node-exporter).
- `vm/app/`: auth-service + core-service + realtime-gateway + node-exporter + cadvisor.
- `vm/datos/`: postgres + redis + rabbitmq + node-exporter.

Los repos de los servicios no se clonan en las VMs: cada compose jala las
imagenes de GHCR.
