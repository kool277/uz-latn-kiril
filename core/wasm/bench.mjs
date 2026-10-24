#!/usr/bin/env node
/* Throughput of the WebAssembly engine vs the reference JS core: node core/wasm/bench.mjs [MiB] */
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { instantiate } from './uztranslit-wasm.mjs';

const ref = createRequire(import.meta.url)('../js/uztranslit.js');
const U = await instantiate(readFileSync(new URL('./build/uztranslit.wasm', import.meta.url)));
const fixtures = JSON.parse(readFileSync(new URL('../../spec/fixtures.json', import.meta.url), 'utf8'));
const mib = Number(process.argv[2] || 16);

function corpus(script) {
  const lines = fixtures.cases.filter(c => c.from === script).map(c => c.in);
  const parts = [];
  let len = 0, i = 0;
  while (len < mib * 1024 * 1024) { const s = lines[i++ % lines.length] + (i % 7 ? ' ' : '\n'); parts.push(s); len += s.length; }
  return parts.join('');
}
const text = { cyr: corpus('cyr'), lat: corpus('lat'), new: corpus('new') };

function time(fn) {
  fn(); // warm-up
  const t = performance.now();
  const r = fn();
  return [performance.now() - t, r];
}
console.log(`${mib} MiB of text per direction (${(text.lat.length / 1e6).toFixed(1)}M UTF-16 code units)`);
console.log('direction   js ms   wasm ms   speed-up  same output');
for (const [from, to] of [['cyr', 'lat'], ['cyr', 'new'], ['lat', 'cyr'], ['new', 'cyr'], ['lat', 'new'], ['new', 'lat']]) {
  const [tj, rj] = time(() => ref.convert(text[from], from, to));
  const [tw, rw] = time(() => U.convert(text[from], from, to));
  console.log(`${from}->${to}`.padEnd(10), String(Math.round(tj)).padStart(6), String(Math.round(tw)).padStart(9),
    (tj / tw).toFixed(1).padStart(9) + 'x', ' ', rj === rw);
}

// the plain-JS fallback (wasm2js translation of the same engine)
const { fromExports } = await import('./uztranslit-wasm.mjs');
const F = fromExports(await import('./build/uztranslit.engine.js'));
console.log('\nfallback   js ms   engine.js ms   ratio');
for (const [from, to] of [['cyr', 'lat'], ['lat', 'cyr'], ['lat', 'new']]) {
  const [tj] = time(() => ref.convert(text[from], from, to));
  const [tf, rf] = time(() => F.convert(text[from], from, to));
  console.log(`${from}->${to}`.padEnd(10), String(Math.round(tj)).padStart(6), String(Math.round(tf)).padStart(14),
    (tj / tf).toFixed(1).padStart(7) + 'x', rf === ref.convert(text[from], from, to));
}
