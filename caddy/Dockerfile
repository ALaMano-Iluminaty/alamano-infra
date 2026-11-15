# Caddy con el plugin de rate limit (HU-Q4). La imagen oficial no lo trae, asi que se
# compila con xcaddy. La publica el CI de este repo en GHCR; en la VM no se compila.
FROM caddy:2-builder-alpine AS builder
RUN xcaddy build --with github.com/mholt/caddy-ratelimit

FROM caddy:2-alpine
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
# Bajar privilegios: la imagen base trae el usuario 'caddy' y el binario con
# cap_net_bind_service, por lo que puede escuchar en 80/443 sin ser root.
USER caddy
