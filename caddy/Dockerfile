# Caddy con el plugin de rate limit (HU-Q4). La imagen oficial no lo trae, asi que se
# compila con xcaddy. La publica el CI de este repo en GHCR; en la VM no se compila.
FROM caddy:2-builder-alpine AS builder
RUN xcaddy build --with github.com/mholt/caddy-ratelimit

FROM caddy:2-alpine
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
