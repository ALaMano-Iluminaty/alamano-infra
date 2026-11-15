# HU-Q1: Caddy como balanceador con verificacion de salud para 2 Core y 2 Gateway.
# Se usa con docker-compose.ha.yml. Los upstreams se pueden cambiar por variable de
# entorno para la topologia de 4 VMs (ver docs/topologia-4-vms.md), por ejemplo:
#   CORE_UPSTREAMS="10.0.1.4:8082 10.0.1.5:8082"
{
	order rate_limit before reverse_proxy
}

{$DOMAIN} {
	@api path /auth/* /api/*
	rate_limit @api {
		zone borde {
			key {remote_host}
			events 100
			window 1m
		}
		log_key
	}

	handle /auth/* {
		reverse_proxy {$AUTH_UPSTREAMS:auth-service:8081} {
			health_uri /actuator/health
			health_interval 10s
			health_timeout 3s
		}
	}

	# El healthcheck cada 10 s cumple el AC: una instancia caida sale del reparto en <= 10 s.
	# Entre tanto, un intento fallido se reintenta en la otra instancia (lb_try_duration).
	handle /api/* {
		reverse_proxy {$CORE_UPSTREAMS:core-service:8082 core-service-2:8082} {
			lb_policy least_conn
			lb_try_duration 5s
			lb_try_interval 250ms
			health_uri /actuator/health
			health_interval 10s
			health_timeout 3s
			fail_duration 30s
			max_fails 1
		}
	}

	# WebSocket: la sesion STOMP vive en la instancia que acepto el handshake; si esa cae,
	# el navegador reconecta y Caddy lo manda a la que sigue sana.
	handle /ws* {
		reverse_proxy {$GATEWAY_UPSTREAMS:realtime-gateway:8083 realtime-gateway-2:8083} {
			lb_policy least_conn
			health_uri /actuator/health
			health_interval 10s
			health_timeout 3s
			fail_duration 30s
			max_fails 1
			transport http {
				read_timeout 1h
				write_timeout 1h
			}
		}
	}

	handle /grafana* {
		reverse_proxy {$GRAFANA_UPSTREAM:grafana:3000}
	}

	handle {
		reverse_proxy {$FRONTEND_UPSTREAM:frontend:80}
	}
}
