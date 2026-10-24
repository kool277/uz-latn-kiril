#!/usr/bin/env node
/* Post-build: allows the inline <script> elements Angular emits (the import map with subresource-integrity
 * hashes) in the Content-Security-Policy by their SHA-256, instead of 'unsafe-inline', then refreshes the
 * service worker's hash of index.html so offline caching still validates. Runs after `ng build`. */
import { createHash } from 'node:crypto';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const dist = join(dirname(fileURLToPath(import.meta.url)), '..', 'dist', 'uztranslit-web', 'browser');
const indexPath = join(dist, 'index.html');
let html = readFileSync(indexPath, 'utf8');

const hashes = [...html.matchAll(/<script(?![^>]*\ssrc=)[^>]*>([\s\S]*?)<\/script>/g)]
  .map(m => `'sha256-${createHash('sha256').update(m[1], 'utf8').digest('base64')}'`);
const csp = /(<meta http-equiv="Content-Security-Policy" content="[^"]*script-src 'self')/;
if (!csp.test(html)) throw new Error('csp-hash: Content-Security-Policy meta tag not found');
html = html.replace(csp, `$1${hashes.map(h => ' ' + h).join('')}`);
writeFileSync(indexPath, html);

const ngswPath = join(dist, 'ngsw.json');
if (existsSync(ngswPath)) {
  const ngsw = JSON.parse(readFileSync(ngswPath, 'utf8'));
  const key = Object.keys(ngsw.hashTable).find(k => k.endsWith('/index.html'));
  if (key) ngsw.hashTable[key] = createHash('sha1').update(readFileSync(indexPath)).digest('hex');
  writeFileSync(ngswPath, JSON.stringify(ngsw, null, 2));
}
console.log(`csp-hash: ${hashes.length} inline script(s) allowed by hash`);
