#!/usr/bin/env node
/* Writes build/differential.json: random texts converted by the reference core/js/uztranslit.js in every direction
 * with random options, plus detection results. Every port's test runner checks itself against it when the file
 * exists (CI generates it first); the spec fixtures stay the contract, this corpus catches what they miss.
 *   node tools/make_differential.mjs [texts=2000] [seed=20261021] */
import { mkdirSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { DIRECTIONS, randomOptions, randomText, rng } from './random-text.mjs';

const ref = createRequire(import.meta.url)('../core/js/uztranslit.js');
const texts = Number(process.argv[2] || 2000);
const seed = Number(process.argv[3] || 20261021);
const rnd = rng(seed);
const cases = [], detect = [];
for (let i = 0; i < texts; i++) {
  const text = randomText(rnd);
  const options = randomOptions(rnd);
  for (const [from, to] of DIRECTIONS) cases.push({ from, to, options, in: text, out: ref.convert(text, from, to, options) });
  detect.push({ in: text, expect: ref.detect(text) });
}
const out = new URL('../build/differential.json', import.meta.url);
mkdirSync(new URL('../build/', import.meta.url), { recursive: true });
writeFileSync(out, JSON.stringify({
  generator: 'tools/make_differential.mjs', reference: `core/js/uztranslit.js v${ref.VERSION}`, seed, cases, detect
}));
console.log(`wrote build/differential.json: ${cases.length} conversions, ${detect.length} detections (seed ${seed})`);
