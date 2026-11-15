/**
 * HU-Q6: 50 barberos envían ubicación cada 3 s, 250 clientes suscritos a /topic/map, 10 min.
 *
 * Requisitos del sistema antes de correr:
 *   - Gateway, Core y RabbitMQ levantados.
 *   - 50 barberos con un servicio activo (el Core descarta ubicaciones sin servicio en curso).
 *   - tokens.json generado con gen-tokens.sh.
 *
 * Métricas que se verifican:
 *   - location_roundtrip_ms p(95) < 500 ms
 *   - connection_errors rate < 1 %
 *   - messages_received count > 0
 *
 * Correr:
 *   k6 run --env GATEWAY_URL=ws://host:8083/ws ubicacion-realtime.js
 */

import ws from 'k6/ws';
import { check } from 'k6';
import { Trend, Counter, Rate } from 'k6/metrics';
import { SharedArray } from 'k6/data';

// ── Métricas personalizadas ──────────────────────────────────────────────────
const locationRoundtrip = new Trend('location_roundtrip_ms', true);
const connectionLatency  = new Trend('ws_connection_latency_ms', true);
const messagesSent       = new Counter('messages_sent');
const messagesReceived   = new Counter('messages_received');
const connectionErrors   = new Rate('connection_errors');

// ── Tokens (generados con gen-tokens.sh) ────────────────────────────────────
const tokens = new SharedArray('tokens', () => JSON.parse(open('./tokens.json')));

// ── Configuración del test ───────────────────────────────────────────────────
const TEST_DURATION = '10m';
const LOCATION_INTERVAL_MS = 3000;

export const options = {
  scenarios: {
    barberos: {
      executor: 'constant-vus',
      vus: 50,
      duration: TEST_DURATION,
      env: { ROLE: 'PROFESSIONAL' },
      tags: { scenario: 'barberos' },
    },
    clientes: {
      executor: 'constant-vus',
      vus: 250,
      duration: TEST_DURATION,
      env: { ROLE: 'CLIENT' },
      tags: { scenario: 'clientes' },
    },
  },
  thresholds: {
    location_roundtrip_ms:  ['p(95)<500'],
    connection_errors:      ['rate<0.01'],
    messages_received:      ['count>0'],
  },
};

const GATEWAY_URL = __ENV.GATEWAY_URL || 'ws://localhost:8083/ws';

// ── Helpers STOMP ────────────────────────────────────────────────────────────
function frame(command, headers = {}, body = '') {
  let f = command + '\n';
  for (const [k, v] of Object.entries(headers)) {
    f += `${k}:${v}\n`;
  }
  return f + '\n' + body + '\0';
}

function isCommand(data, command) {
  return typeof data === 'string' && data.startsWith(command + '\n');
}

// Coordenadas aleatorias en Buenos Aires (rango de ~11 km)
function randomCoord() {
  return {
    latitude:  -34.6 + (Math.random() - 0.5) * 0.1,
    longitude: -58.4 + (Math.random() - 0.5) * 0.1,
  };
}

// ── Escenario barbero ────────────────────────────────────────────────────────
function runBarbero(token, vuIndex) {
  let connectedAt = Date.now();
  let lastSendTime = 0;

  const res = ws.connect(GATEWAY_URL, {}, (socket) => {
    socket.on('open', () => {
      socket.send(frame('CONNECT', {
        'accept-version': '1.2',
        'heart-beat': '10000,10000',
        Authorization: `Bearer ${token}`,
      }));
    });

    socket.on('message', (data) => {
      if (isCommand(data, 'CONNECTED')) {
        connectionLatency.add(Date.now() - connectedAt);

        // Suscripción al mapa para medir el roundtrip de cada ubicación enviada
        socket.send(frame('SUBSCRIBE', {
          id: `sub-map-b${vuIndex}`,
          destination: '/topic/map',
        }));

        // Primera ubicación tras 500 ms, luego cada 3 s
        socket.setTimeout(function sendLoop() {
          const coord = randomCoord();
          const body = JSON.stringify(coord);
          lastSendTime = Date.now();
          socket.send(frame('SEND', {
            destination: '/app/location',
            'content-type': 'application/json',
            'content-length': body.length,
          }, body));
          messagesSent.add(1);
          socket.setTimeout(sendLoop, LOCATION_INTERVAL_MS);
        }, 500);
        return;
      }

      if (isCommand(data, 'MESSAGE') && lastSendTime > 0) {
        locationRoundtrip.add(Date.now() - lastSendTime);
        messagesReceived.add(1);
        lastSendTime = 0;
      }

      if (isCommand(data, 'ERROR')) {
        connectionErrors.add(1);
      }
    });

    socket.on('error', () => connectionErrors.add(1));
    socket.on('close', () => {});
  });

  check(res, { 'handshake 101': (r) => r && r.status === 101 });
}

// ── Escenario cliente ────────────────────────────────────────────────────────
function runCliente(token, vuIndex) {
  let connectedAt = Date.now();

  const res = ws.connect(GATEWAY_URL, {}, (socket) => {
    socket.on('open', () => {
      socket.send(frame('CONNECT', {
        'accept-version': '1.2',
        'heart-beat': '10000,10000',
        Authorization: `Bearer ${token}`,
      }));
    });

    socket.on('message', (data) => {
      if (isCommand(data, 'CONNECTED')) {
        connectionLatency.add(Date.now() - connectedAt);
        socket.send(frame('SUBSCRIBE', {
          id: `sub-map-c${vuIndex}`,
          destination: '/topic/map',
        }));
        return;
      }

      if (isCommand(data, 'MESSAGE')) {
        messagesReceived.add(1);
      }

      if (isCommand(data, 'ERROR')) {
        connectionErrors.add(1);
      }
    });

    socket.on('error', () => connectionErrors.add(1));
    socket.on('close', () => {});
  });

  check(res, { 'handshake 101': (r) => r && r.status === 101 });
}

// ── Punto de entrada ─────────────────────────────────────────────────────────
export default function () {
  const role     = __ENV.ROLE;
  const vuIndex  = __VU - 1;

  if (role === 'PROFESSIONAL') {
    const token = tokens.barberos[vuIndex % tokens.barberos.length];
    runBarbero(token, vuIndex);
  } else {
    const token = tokens.clientes[vuIndex % tokens.clientes.length];
    runCliente(token, vuIndex);
  }
}
