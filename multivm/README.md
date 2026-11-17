# Despliegue en 3 VMs (HU-Q1: disponibilidad)

La cuota de Azure for Students en Brazil South es de 6 vCPU, asi que en vez de las 4 VMs de
`docs/topologia-4-vms.md` se usan 3 de 2 vCPU: la base de datos comparte VM con la entrada.
No se usa la carpeta `vm/` tal cual porque su compose de datos publica PostgreSQL, Redis y
RabbitMQ en todas las interfaces, y en la VM de entrada (con IP publica) quedarian abiertos.

| VM | IP privada | Corre | Expuesta a internet |
| --- | --- | --- | --- |
| alamano-vm (entrada y datos) | 172.16.0.4 | Caddy, Frontend, Auth, Prometheus, Grafana, PostgreSQL, Redis, RabbitMQ | 80 y 443 (22 solo desde tu IP) |
| alamano-app1 | 172.16.0.5 | Core y Gateway | no |
| alamano-app2 | 172.16.0.6 | Core y Gateway | no |

PostgreSQL, Redis y RabbitMQ se atan a la IP privada (`DATOS_IP`), no a `0.0.0.0`.

## Archivos
- `compose.datos.yml`, `compose.entrada.yml`: en alamano-vm, con `--env-file .env`.
- `compose.app.yml`: en app1 y app2 (`~/alamano-infra/`), con su propio `.env`.
- `Caddyfile`: limite de 100 peticiones por minuto por IP (`RATE_EVENTS`) y reparto entre app1 y app2.
- `prometheus.yml`: raspa por IP privada.
- `deploy-app.sh`: actualiza una VM de aplicacion.

## `.env`
- alamano-vm: `DOMAIN`, contrasenas de Postgres y RabbitMQ, `APP1_IP`, `APP2_IP`, `DATOS_IP`,
  `GOOGLE_CLIENT_ID`, `ADMIN_EMAILS`, `RATE_EVENTS`, `GRAFANA_ADMIN_PASSWORD`.
- app1 y app2: `APP_IP` (la suya), `DATOS_IP`, `HOSTNAME`, `CORE_DB_PASSWORD`, `RABBITMQ_PASSWORD`,
  `DOMAIN`. Nunca se suben a git.
- La llave JWT privada solo esta en alamano-vm; app1 y app2 llevan solo `keys/jwt-public.pem`.

## Despliegue automatico
Cada repo publica su imagen al integrar y su job `Desplegar en la VM` ejecuta `scripts/deploy.sh`
en alamano-vm. Con `APP1_IP` y `APP2_IP` en el `.env`, ese script actualiza datos, luego app1 y
app2 una a la vez (la otra sigue atendiendo) y al final la entrada. Si una VM de aplicacion no
queda sana, se detiene sin tocar la siguiente.

Para llegar a las VMs de aplicacion, alamano-vm usa su propia llave `~/.ssh/deploy_apps`
(la privada nunca sale de esa VM). La publica va en `~/.ssh/authorized_keys` de app1 y app2.

## Prueba de caida
`bash scripts/prueba-caida.sh alamano-core-service` en app1 o app2, con k6 corriendo.
