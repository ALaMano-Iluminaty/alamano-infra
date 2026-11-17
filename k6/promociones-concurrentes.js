/**
 * HU-Q8: 200 clientes reclaman a la vez una promocion de 50 cupos, 5 rondas cada 60 s,
 * con una promocion nueva en cada ronda. Por ronda deben entregarse EXACTAMENTE 50
 * cupos (200) y 150 rechazos (409); nunca mas de 50 ni un 5xx.
 *
 * IMPORTANTE: los 200 clientes salen de una sola IP. El limite del borde (HU-Q4, 100
 * por minuto por IP) los cortaria con 429, asi que durante la prueba hay que subir
 * RATE_EVENTS en el .env de la VM de entrada y volver a 100 al terminar.
 *
 * Correr desde alamano-infra:
 *   docker run --rm -i --network host -v "$PWD/k6:/k6" -w /k6 \
 *     -e BASE=https://alamano.brazilsouth.cloudapp.azure.com grafana/k6 run promociones-concurrentes.js
 *
 * Variables: BASE, BARBERO_BASE (primer barbero que publica), CLIENTES (200), CUPOS (50),
 * RONDAS (5), INTERVALO_S (60).
 */
import http from 'k6/http';
import { sleep } from 'k6';
import { Counter, Rate } from 'k6/metrics';

const BASE = __ENV.BASE || 'http://localhost';
const BARBERO_BASE = parseInt(__ENV.BARBERO_BASE || '0', 10);
const CLIENTES = parseInt(__ENV.CLIENTES || '200', 10);
const CUPOS = parseInt(__ENV.CUPOS || '50', 10);
const RONDAS = parseInt(__ENV.RONDAS || '5', 10);
const INTERVALO_S = parseInt(__ENV.INTERVALO_S || '60', 10);

// tokens.json es un objeto {barberos, clientes}; SharedArray solo admite arrays.
const tokens = JSON.parse(open('./tokens.json'));

const cuposEntregados = new Counter('cupos_entregados');
const rechazos409 = new Counter('rechazos_409');
const inesperados = new Rate('respuestas_inesperadas');
const errores5xx = new Rate('errores_5xx');

const thresholds = {
  respuestas_inesperadas: ['rate==0'],
  errores_5xx: ['rate==0'],
};
for (let r = 0; r < RONDAS; r++) thresholds[`cupos_entregados{ronda:${r}}`] = [`count==${CUPOS}`];

export const options = {
  scenarios: {
    reclamos: {
      executor: 'per-vu-iterations',
      vus: CLIENTES,
      iterations: RONDAS,
      maxDuration: `${RONDAS * INTERVALO_S + 120}s`,
    },
  },
  thresholds,
};

const JSON_HEADERS = { 'Content-Type': 'application/json' };
const auth = (t) => ({ headers: { ...JSON_HEADERS, Authorization: `Bearer ${t}` } });

export function setup() {
  // Una promocion nueva por ronda, cada una publicada por un barbero distinto.
  const promos = [];
  for (let r = 0; r < RONDAS; r++) {
    const res = http.post(
      `${BASE}/api/promotions`,
      JSON.stringify({ description: `Carga Q8 ronda ${r + 1} ${Date.now()}`, totalSlots: CUPOS }),
      auth(tokens.barberos[BARBERO_BASE + r]),
    );
    const id = res.status < 300 ? res.json('id') : null;
    if (!id) throw new Error(`no se pudo publicar la promocion de la ronda ${r + 1}: ${res.status} ${res.body}`);
    promos.push(id);
  }
  return { t0: Date.now() + 5000, promos };
}

export default function (data) {
  const ronda = __ITER;
  const espera = data.t0 + ronda * INTERVALO_S * 1000 - Date.now();
  if (espera > 0) sleep(espera / 1000);

  const token = tokens.clientes[(__VU - 1) % tokens.clientes.length];
  const res = http.post(`${BASE}/api/promotions/${data.promos[ronda]}/claim`, null,
    { ...auth(token), tags: { ronda: String(ronda) } });

  cuposEntregados.add(res.status === 200 ? 1 : 0, { ronda: String(ronda) });
  if (res.status === 409) rechazos409.add(1, { ronda: String(ronda) });
  inesperados.add(res.status !== 200 && res.status !== 409);
  errores5xx.add(res.status >= 500 || res.status === 0);
}
