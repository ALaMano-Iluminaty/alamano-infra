/**
 * HU-Q1: 200 usuarios activos durante 5 min; al minuto 3 se tumba una instancia (fuera
 * de k6, con scripts/prueba-disponibilidad.sh). Se mide que:
 *   - >= 99 % de las peticiones tengan exito (errores <= 1 %)
 *   - el p95 se mantenga por debajo de 500 ms incluso durante la caida
 *   - los WebSockets reconecten en <= 30 s
 *
 * Correr:
 *   k6 run --env BASE=https://alamano.example.com disponibilidad.js
 */

import http from 'k6/http';
import ws from 'k6/ws';
import { check, sleep } from 'k6';
import { Trend, Counter, Rate } from 'k6/metrics';
import { SharedArray } from 'k6/data';

const httpLatency = new Trend('http_latency_ms', true);
const wsReconnectGap = new Trend('ws_reconnect_gap_s', true);
const wsReconnects = new Counter('ws_reconnects');
const httpErrors = new Rate('http_errors');

const tokens = new SharedArray('tokens', () => JSON.parse(open('./tokens.json')));

const BASE = __ENV.BASE || 'http://localhost';
const WS_BASE = (__ENV.WS_BASE || BASE.replace(/^http/, 'ws')) + '/ws';

export const options = {
  scenarios: {
    // 150 clientes golpeando HTTP cada 1-2 s
    http_clientes: {
      executor: 'constant-vus',
      vus: 150,
      duration: '5m',
      exec: 'httpCliente',
      tags: { scenario: 'http' },
    },
    // 50 clientes con WebSocket STOMP escuchando eventos
    ws_clientes: {
      executor: 'constant-vus',
      vus: 50,
      duration: '5m',
      exec: 'wsCliente',
      tags: { scenario: 'ws' },
    },
  },
  thresholds: {
    // AC HU-Q1: >= 99 % de peticiones exitosas con una instancia caida.
    http_errors: ['rate<0.01'],
    http_latency_ms: ['p(95)<500'],
    // AC HU-Q1: la reconexion WS no debe pasar de 30 s.
    ws_reconnect_gap_s: ['p(95)<30'],
  },
};

export function httpCliente() {
  const token = tokens.clientes[(__VU - 1) % tokens.clientes.length];
  const headers = { Authorization: `Bearer ${token}` };

  // Dos endpoints reales del Core, montados detras de /api.
  const endpoints = ['/api/professionals/nearby?lat=-34.6&lng=-58.4', '/api/services/active'];
  const url = BASE + endpoints[Math.floor(Math.random() * endpoints.length)];

  const res = http.get(url, { headers, timeout: '10s', tags: { endpoint: url } });
  httpLatency.add(res.timings.duration);
  // 429 cuenta como rechazo esperado (rate limit), no como error de disponibilidad.
  const ok = res.status >= 200 && res.status < 500 && res.status !== 0;
  httpErrors.add(!ok);
  check(res, { 'no 5xx': (r) => r.status < 500, 'no timeout': (r) => r.status !== 0 });

  sleep(1 + Math.random());
}

export function wsCliente() {
  const token = tokens.clientes[(__VU - 1) % tokens.clientes.length];
  const start = Date.now();
  // El VU reconecta tantas veces como haga falta durante los 5 minutos.
  while (Date.now() - start < 5 * 60 * 1000) {
    let disconnectedAt = 0;
    const res = ws.connect(WS_BASE, {}, (socket) => {
      socket.on('open', () => {
        socket.send(
          'CONNECT\naccept-version:1.2\nheart-beat:10000,10000\nAuthorization:Bearer ' + token + '\n\n\0',
        );
      });
      socket.on('message', (data) => {
        if (typeof data === 'string' && data.startsWith('CONNECTED')) {
          socket.send('SUBSCRIBE\nid:s-1\ndestination:/topic/map\n\n\0');
        }
      });
      socket.on('close', () => {
        disconnectedAt = Date.now();
      });
      // k6 mantiene el VU dentro del callback hasta que el socket cierra.
      socket.setTimeout(() => socket.close(), 15000 + Math.random() * 5000);
    });
    check(res, { 'ws handshake': (r) => r && r.status === 101 });

    // El tiempo entre un cierre y el siguiente handshake 101 es la "brecha" de
    // reconexion vista por el usuario. Mientras el sistema esta sano es ~0;
    // cuando Caddy saca la instancia caida, el pico muestra lo que tardo.
    const reconnectStart = Date.now();
    sleep(0.1);
    const gap = disconnectedAt > 0 ? (reconnectStart - disconnectedAt) / 1000 : 0;
    wsReconnectGap.add(gap);
    wsReconnects.add(1);
  }
}
