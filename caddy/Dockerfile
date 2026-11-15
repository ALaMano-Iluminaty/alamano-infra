# Caddy con el plugin de rate limit (HU-Q4). La imagen oficial no lo trae, asi que se
# compila con xcaddy. La publica el CI de este repo en GHCR; en la VM no se compila.
FROM caddy:2-builder-alpine AS builder
RUN xcaddy build --with github.com/mholt/caddy-ratelimit

FROM caddy:2-alpine
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
# El hotspot S6471 (contenedor como root) queda marcado como Safe en SonarCloud.
# La imagen base no provee un usuario no-root y Caddy necesita ligar 80/443 para
# TLS. Alternativas (setcap + adduser + chown de /data y /config) rompian el
# arranque en la VM, por eso se mantiene el comportamiento por defecto.
