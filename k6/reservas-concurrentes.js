/**
 * HU-Q7: 30 clientes reservan a la vez al mismo barbero, 10 rondas cada 30 s, un
 * barbero distinto por ronda. Por ronda debe haber EXACTAMENTE una reserva (201) y
 * 29 rechazos 409 (professional_busy); nunca un 5xx.
 *
 * Requiere k6/tokens.json (gen-tokens.sh): usa barbero-1..N y cliente-1..30.
 *
 * Correr desde alamano-infra:
 *   docker run --rm -i --network host -v "$PWD/k6:/k6" -w /k6 \
 *     -e BASE=https://alamano.brazilsouth.cloudapp.azure.com grafana/k6 run reservas-concurrentes.js
 *
 * Variables: BASE, BARBERO_BASE (indice del primer barbero; cambialo en cada corrida,
 * porque el barbero reservado queda ocupado), CLIENTES (30), RONDAS (10), INTERVALO_S (30).
 */
import http from 'k6/http';
import { sleep } from 'k6';
import { Counter, Rate } from 'k6/metrics';

const BASE = __ENV.BASE || 'http://localhost';
const BARBERO_BASE = parseInt(__ENV.BARBERO_BASE || '0', 10);
const CLIENTES = parseInt(__ENV.CLIENTES || '30', 10);
const RONDAS = parseInt(__ENV.RONDAS || '10', 10);
const INTERVALO_S = parseInt(__ENV.INTERVALO_S || '30', 10);

// tokens.json es un objeto {barberos, clientes}; SharedArray solo admite arrays.
const tokens = JSON.parse(open('./tokens.json'));

const reservasGanadas = new Counter('reservas_ganadas');
const rechazos409 = new Counter('rechazos_409');
const inesperados = new Rate('respuestas_inesperadas');
const errores5xx = new Rate('errores_5xx');

const thresholds = {
  http_req_duration: ['p(95)<=300'],
  respuestas_inesperadas: ['rate==0'],
  errores_5xx: ['rate==0'],
};
for (let r = 0; r < RONDAS; r++) thresholds[`reservas_ganadas{ronda:${r}}`] = ['count==1'];

export const options = {
  scenarios: {
    reservas: {
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
  // Cada barbero de la prueba se conecta y queda disponible.
  for (let r = 0; r < RONDAS; r++) {
    const res = http.post(
      `${BASE}/api/professionals/me/online`,
      JSON.stringify({ latitude: -34.6, longitude: -58.4 }) /* lejos de Bogota: no ensucia el mapa de la demo */,
      auth(tokens.barberos[BARBERO_BASE + r]),
    );
    if (res.status !== 200 && res.status !== 201) {
      throw new Error(`el barbero ${BARBERO_BASE + r + 1} no pudo conectarse: ${res.status} ${res.body}`);
    }
  }
  return { t0: Date.now() + 5000 };
}

export default function (data) {
  const ronda = __ITER;
  // Todos los clientes disparan en el mismo instante de cada ronda.
  const espera = data.t0 + ronda * INTERVALO_S * 1000 - Date.now();
  if (espera > 0) sleep(espera / 1000);

  const token = tokens.clientes[(__VU - 1) % tokens.clientes.length];
  const barbero = `barbero-${BARBERO_BASE + ronda + 1}`;
  const res = http.post(`${BASE}/api/services`, JSON.stringify({ professionalId: barbero }),
    { ...auth(token), tags: { ronda: String(ronda) } });

  reservasGanadas.add(res.status === 201 ? 1 : 0, { ronda: String(ronda) });
  if (res.status === 409) rechazos409.add(1, { ronda: String(ronda) });
  inesperados.add(res.status !== 201 && res.status !== 409);
  errores5xx.add(res.status >= 500 || res.status === 0);
}
