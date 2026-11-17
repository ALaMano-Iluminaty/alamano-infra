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

const latencia = new Trend('latencia_cercanos_ms', true);
const errores = new Rate('errores_cercanos');

// tokens.json es un objeto {barberos, clientes}; SharedArray solo admite arrays.
const tokens = JSON.parse(open('./tokens.json'));
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

// 20 zonas fijas (cuadricula de 5 x 4 sobre Bogota, separadas 0,02 grados: cada una cae
// en una celda distinta de la cache del Core). Son deterministas a proposito: este codigo
// se ejecuta una vez POR USUARIO VIRTUAL, y con Math.random cada uno tendria sus propias
// zonas y la prueba no mediria la cache compartida.
const ZONAS = Array.from({ length: 20 }, (_, i) => ({
  lat: (4.61 + (i % 5) * 0.02).toFixed(4),
  lng: (-74.1 + Math.floor(i / 5) * 0.02).toFixed(4),
}));

export default function () {
  const token = tokens.clientes[(__VU - 1) % tokens.clientes.length];
  const zona = ZONAS[(__VU + __ITER) % ZONAS.length];
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
