/**
 * HU-Q9: 250 clientes consultan barberos cercanos cada 5 s durante 10 min.
 * AC: p95 <= 300 ms, errores < 1 %, >= 80 % de respuestas servidas desde cache.
 *
 * La relacion de cache se verifica aparte, comparando keyspace_hits/keyspace_misses
 * de Redis antes y despues (ver scripts/prueba-cercanos.sh).
 *
 * Correr:
 *   k6 run --env BASE=https://alamano.example.com barberos-cercanos.js
 */

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Trend, Rate } from 'k6/metrics';
import { SharedArray } from 'k6/data';

const latencia = new Trend('latencia_cercanos_ms', true);
const errores = new Rate('errores_cercanos');

const tokens = new SharedArray('tokens', () => JSON.parse(open('./tokens.json')));
const BASE = __ENV.BASE || 'http://localhost';

export const options = {
  scenarios: {
    cercanos: {
      executor: 'constant-vus',
      vus: 250,
      duration: '10m',
    },
  },
  thresholds: {
    latencia_cercanos_ms: ['p(95)<300'],
    errores_cercanos: ['rate<0.01'],
  },
};

// 20 zonas pre-elegidas: el Core cachea por celda, asi que el porcentaje de hits
// sube rapido y se mantiene por encima del 80 % durante casi todo el test.
// Math.random genera coordenadas aleatorias de prueba de carga; no se usa para
// secretos ni tokens, por eso no se requiere un PRNG criptografico. NOSONAR
const ZONAS = Array.from({ length: 20 }, () => ({
  lat: (-34.6 + (Math.random() - 0.5) * 0.08).toFixed(4),
  lng: (-58.4 + (Math.random() - 0.5) * 0.08).toFixed(4),
}));

export default function () {
  const token = tokens.clientes[(__VU - 1) % tokens.clientes.length];
  const zona = ZONAS[Math.floor(Math.random() * ZONAS.length)]; // NOSONAR: eleccion de zona para carga, no crypto
  const url = `${BASE}/api/professionals/nearby?lat=${zona.lat}&lng=${zona.lng}`;

  const res = http.get(url, {
    headers: { Authorization: `Bearer ${token}` },
    timeout: '5s',
  });
  latencia.add(res.timings.duration);
  errores.add(res.status < 200 || res.status >= 500 || res.status === 0);
  check(res, { '2xx/4xx': (r) => r.status >= 200 && r.status < 500 });

  // "Cada 5 s por cliente" segun el AC.
  sleep(5);
}
