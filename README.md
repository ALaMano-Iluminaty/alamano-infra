# alamano-infra

Todo lo necesario para levantar ALaManoApp completo: Postgres, Redis, RabbitMQ, los
servicios Java, el frontend y el punto de entrada. En la VM, Caddy adelante resuelve el
HTTPS. No hay código de negocio aquí: este repo solo describe cómo se arma el sistema.

## Estructura esperada

Los repos van como hermanos, en la misma carpeta:

    ALaMano/
      alamano-infra/              <- este repo
      alamano-auth-service/
      alamano-core-service/
      alamano-realtime-gateway/
      alamano-frontend/

Cada servicio necesita un `Dockerfile` en su raíz. `alamano-auth-service` y
`alamano-core-service` ya lo tienen. Para los otros dos están `Dockerfile.template` y
`Dockerfile.frontend.template`.

## Arrancar en local

```bash
bash scripts/gen-keys.sh      # par RS256 en ./keys, fuera de git
cp .env.example .env
docker compose up --build     # http://localhost:8080
bash scripts/smoke.sh         # prueba de humo de punta a punta
```

El Gateway y el Frontend están detrás de un perfil, porque todavía no tienen
`Dockerfile`. Cuando lo tengan:

```bash
docker compose --profile gateway --profile frontend up --build
```

## Rutas

| Ruta | Va a | Nota |
|---|---|---|
| `/` | frontend | |
| `/auth/*` | auth-service `:8081` | el prefijo **no** se recorta |
| `/api/*` | core-service `:8082` | el prefijo **no** se recorta |
| `/ws` | realtime-gateway `:8083` | WebSocket; confirmar la ruta exacta |

Postgres, Redis y RabbitMQ solo escuchan en `127.0.0.1`: nunca quedan expuestos a
internet. El panel de RabbitMQ queda en `localhost:15672`.

## Las llaves RS256

Auth firma con la privada; Core y el Gateway verifican con la pública. Los tres montan
la misma carpeta `./keys`, así que **la llave pública tiene que ser la pareja de la
privada que usa Auth**, o todos los tokens se rechazan con 401.

Cada servicio la pide distinto, y es fácil equivocarse:

| Servicio | Variable | Valor |
|---|---|---|
| auth-service | `JWT_PRIVATE_KEY_PATH` y `JWT_PUBLIC_KEY_PATH` | ruta simple: `/keys/jwt-private.pem` |
| core-service | `JWT_PUBLIC_KEY_LOCATION` | recurso de Spring: `file:/keys/jwt-public.pem` |

El Core la lee como recurso de Spring, por eso lleva el prefijo `file:` y la variable se
llama `LOCATION`, no `PATH`. Con el nombre equivocado la variable se ignora, el Core usa
la llave de prueba que trae empaquetada y **rechaza todos los tokens**.

## Desplegar en la VM

```bash
bash scripts/bootstrap-vm.sh    # una sola vez: Docker y 2 GB de swap
# clonar los repos en ~/alamano, generar llaves y escribir el .env real
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --build
```

En el `.env` de la VM: `DOMAIN` con el nombre DNS real, `POSTGRES_PORT=5432` y **todas**
las contraseñas cambiadas (`openssl rand -base64 18`). La llave privada se genera ahí y
no sale de la VM.

Abre solo los puertos 22, 80 y 443. Caddy pide y renueva el certificado solo la primera
vez que alguien entra por el dominio.

El HTTPS no es opcional: sin él el navegador bloquea la geolocalización del mapa y los
WebSockets seguros.

Para actualizar después de un merge: `bash scripts/deploy.sh`.

## Scripts

| Script | Para qué |
|---|---|
| `gen-keys.sh` | Genera el par RS256 en `./keys`. No pisa unas que ya existan. |
| `bootstrap-vm.sh` | Prepara una VM Ubuntu nueva: Docker y swap. |
| `deploy.sh` | `git pull` de todos los repos y reconstruye lo que cambió. |
| `smoke.sh` | Registro, login, publicar promoción y 401 sin token. `BASE=https://... bash scripts/smoke.sh` |

## Reglas

- `keys/` y `.env` nunca se suben a git.
- Las llaves se generan con `openssl genpkey` (PKCS#8). Con `genrsa` sale PKCS#1 y los
  servicios no lo leen.
- Auth y Core no comparten tablas: cada uno tiene su esquema y su usuario de Postgres,
  y cada usuario tiene revocado el acceso al esquema del otro.
- El frontend debe llamar por rutas relativas (`/auth`, `/api`) y `wss://` en producción.
  Si apunta a `localhost`, funciona en tu máquina y se rompe en la VM.

## Sobre las imágenes de GHCR

El CI de cada servicio publica su imagen en GHCR al mergear. El compose las nombra con
esa misma etiqueta, así que `docker compose build` las deja listas para subir. Los
paquetes de una organización nacen privados: si quieres que la VM las descargue en vez
de compilarlas, hay que hacer `docker login ghcr.io` allá o poner el paquete en público.
Por defecto el compose compila desde el código, que no necesita autenticación.
