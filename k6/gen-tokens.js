#!/usr/bin/env node
/**
 * Genera tokens RS256 de prueba para el script k6.
 * Uso: node gen-tokens.js [ruta-a-private.pem]
 * Salida: tokens.json en el mismo directorio.
 */
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const scriptDir = __dirname;

function findKey(arg) {
  const candidates = [
    arg,
    path.join(scriptDir, '..', 'keys', 'jwt-private.pem'),
    path.join(scriptDir, '..', '..', 'alamano-realtime-gateway', 'dev-keys', 'dev-private.pem'),
    path.join(scriptDir, '..', '..', 'alamano-infra', 'keys', 'jwt-private.pem'),
  ].filter(Boolean);
  for (const c of candidates) {
    if (c && fs.existsSync(c)) return c;
  }
  return null;
}

const keyPath = findKey(process.argv[2]);
if (!keyPath) {
  console.error('ERROR: no se encontró la llave privada.');
  console.error('  Pásala como argumento: node gen-tokens.js /ruta/a/jwt-private.pem');
  process.exit(1);
}

const privateKey = fs.readFileSync(keyPath, 'utf8');
const now = Math.floor(Date.now() / 1000);
const exp = now + 7200;

function b64url(buf) {
  return buf.toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
}

function makeToken(sub, role) {
  const header  = b64url(Buffer.from(JSON.stringify({ alg: 'RS256', typ: 'JWT' })));
  const payload = b64url(Buffer.from(JSON.stringify({ sub, role, iat: now, exp })));
  const input = `${header}.${payload}`;
  const sig = b64url(crypto.createSign('RSA-SHA256').update(input).sign(privateKey));
  return `${input}.${sig}`;
}

console.error('Generando 50 tokens de barbero y 250 de cliente...');

const barberos = Array.from({ length: 50  }, (_, i) => makeToken(`barbero-${i + 1}`,  'PROFESSIONAL'));
const clientes = Array.from({ length: 250 }, (_, i) => makeToken(`cliente-${i + 1}`, 'CLIENT'));

const out = path.join(scriptDir, 'tokens.json');
fs.writeFileSync(out, JSON.stringify({ barberos, clientes }, null, 0));
console.error(`Tokens escritos en ${out}`);
