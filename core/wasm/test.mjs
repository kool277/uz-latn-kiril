#!/usr/bin/env node
/* Conformance runner for the WebAssembly port: node core/wasm/test.mjs  (exit code 1 on any failure)
 * Runs against build/uztranslit.wasm and against its plain-JS translation build/uztranslit.engine.js:
 *   1. spec/fixtures.json (cases, roundtrips, detect, optional) — must be 212/212
 *   2. differential test against the reference core/js/uztranslit.js on seeded random text,
 *      every direction and option combination (UZT_ITER=n for more iterations, UZT_SEED=s to replay)
 *   3. convertSegments(): pieces.join('') must equal convert(), non-letters never move between pieces */
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { fromExports, instantiate, VERSION } from './uztranslit-wasm.mjs';

const ref = createRequire(import.meta.url)('../js/uztranslit.js');
const fixtures = JSON.parse(readFileSync(new URL('../../spec/fixtures.json', import.meta.url), 'utf8'));
const show = s => JSON.stringify(s);
const seed0 = Number(process.env.UZT_SEED || 20261021) >>> 0;
const iterations = Number(process.env.UZT_ITER || 4000);

function fixtureSuite(U, label) {
  let pass = 0, fail = 0;
  const check = (id, got, want, extra) => {
    if (got === want) { pass++; return; }
    fail++;
    console.log(`FAIL ${id}${extra ? ' ' + extra : ''}\n   want ${show(want)}\n   got  ${show(got)}`);
  };
  for (const c of fixtures.cases) check(c.id, U.convert(c.in, c.from, c.to), c.out, `${c.from}->${c.to} ${show(c.in)}`);
  for (const r of fixtures.roundtrips) {
    const there = U.convert(r.in, r.from, r.via);
    check(r.id, U.convert(there, r.via, r.from), r.in, `${r.from}->${r.via}->${r.from} via ${show(there)}`);
  }
  for (const d of fixtures.detect) check('detect ' + show(d.in), U.detect(d.in), d.expect);
  for (const o of fixtures.optional) {
    const options = o.feature === 'asciiApostrophe' ? { okina: "'", tutuq: "'" } : { skipUrls: true };
    check('optional/' + o.feature, U.convert(o.in, o.from, o.to, options), o.out);
  }
  console.log(`${pass} passed, ${fail} failed (${label} v${VERSION})`);
  return fail;
}

// ---------------------------------------------------------------- random text
const corpusWords = [];
for (const c of fixtures.cases) corpusWords.push(...c.in.split(/\s+/), ...c.out.split(/\s+/));
const TOKENS = [
  ...'абвгдеёжзийклмнопрстуфхцчшщъыьэюяўқғҳАБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯЎҚҒҲ',
  ...'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZöğşçōõÖĞŞÇŌÕ',
  ..."'ʻʼ‘’`´", ' ', ' ', ' ', '\n', '\t', '\u00a0', '\u2028', '\u3000',
  ...'.,;:!?-()"«»0123456789@/_#', 'http://', 'https://', 'www.', '.uz', 'mail@', '@user', '\u{1F600}', '\uD800',
  'sh', 'SH', 'Sh', 'ch', "o'", "g'", "s'h", 'ts', 'tsiya', 'tsion', 'ye', 'yo', "yo'", 'yu', 'ya',
  'kompyuter', 'obyekt', 'SIRK', 'Abzats', 'yogurt', 'ofitser', 'ShAHAR'
];
const DIRS = [['cyr', 'lat'], ['cyr', 'new'], ['lat', 'cyr'], ['new', 'cyr'], ['lat', 'new'], ['new', 'lat'],
  ['auto', 'cyr'], ['auto', 'lat'], ['auto', 'new'], ['lat', 'lat']];
const NON_LETTERS = /^[\s.,;:!?()"«»0-9#-]*$/;

function randomSuite(U, label) {
  let seed = seed0;
  const rnd = () => { // mulberry32
    seed = (seed + 0x6D2B79F5) >>> 0;
    let t = seed;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
  const pick = a => a[Math.floor(rnd() * a.length)];
  let diffPass = 0, diffFail = 0, segPass = 0, segFail = 0;
  for (let it = 0; it < iterations; it++) {
    const n = 1 + Math.floor(rnd() * 40);
    let text = '';
    for (let i = 0; i < n; i++) text += rnd() < 0.25 ? pick(corpusWords) + ' ' : pick(TOKENS);
    const o = {};
    if (rnd() < 0.3) { o.okina = "'"; o.tutuq = "'"; }
    if (rnd() < 0.05) { o.okina = ''; o.tutuq = ''; }
    for (const k of ['dropHardSignAfterO', 'tsFinal', 'dictionary', 'skipUrls']) if (rnd() < 0.25) o[k] = false;

    for (const [from, to] of DIRS) {
      const want = ref.convert(text, from, to, o);
      const got = U.convert(text, from, to, o);
      if (got === want) diffPass++;
      else if (diffFail++ < 10) console.log(`DIFF ${from}->${to} ${show(o)}\n   in   ${show(text)}\n   want ${show(want)}\n   got  ${show(got)}`);

      const cuts = new Set();
      const k = Math.floor(rnd() * 6);
      for (let i = 0; i < k; i++) cuts.add(Math.floor(rnd() * (text.length + 1)));
      const pieces = [];
      let prev = 0;
      for (const c of [...cuts].sort((a, b) => a - b)) { pieces.push(text.slice(prev, c)); prev = c; }
      pieces.push(text.slice(prev));
      const seg = U.convertSegments(pieces, from, to, o);
      let ok = seg.pieces.length === pieces.length && seg.pieces.join('') === want;
      for (let i = 0; ok && i < pieces.length; i++) if (NON_LETTERS.test(pieces[i]) && seg.pieces[i] !== pieces[i]) ok = false;
      if (ok) segPass++;
      else if (segFail++ < 10) console.log(`SEG ${from}->${to} ${show(o)}\n   pieces ${show(pieces)}\n   want   ${show(want)}\n   got    ${show(seg.pieces)}`);
    }
  }
  console.log(`${diffPass} passed, ${diffFail} failed (${label}: differential vs uztranslit.js, seed ${seed0})`);
  console.log(`${segPass} passed, ${segFail} failed (${label}: convertSegments)`);
  return diffFail + segFail;
}

// many segments and long texts: the input, output and boundary buffers (and wasm memory) must grow on the way
function largeSuite(U, label) {
  let pass = 0, fail = 0;
  const words = ['Тошкент ', 'шаҳри ', 'ОБЪЕКТ', ' ва ', 'кўча', '. ', 'Исҳоқ'];
  for (const n of [1000, 50000, 400000]) {
    const pieces = Array.from({ length: n }, (_, i) => words[i % words.length]);
    const want = ref.convert(pieces.join(''), 'cyr', 'lat');
    const got = U.convertSegments(pieces, 'cyr', 'lat');
    if (got.pieces.length === n && got.pieces.join('') === want) pass++;
    else { fail++; console.log(`LARGE ${label}: ${n} segments do not match`); }
  }
  const long = 'Ўзбекистон Республикаси, Тошкент шаҳри. '.repeat(200000);
  if (U.convert(long, 'cyr', 'new') === ref.convert(long, 'cyr', 'new')) pass++;
  else { fail++; console.log(`LARGE ${label}: ${long.length} code units do not match`); }
  if (U.convert('Шаҳар', 'cyr', 'lat') === 'Shahar') pass++; // small again after growing
  else { fail++; console.log(`LARGE ${label}: small input after large ones`); }
  console.log(`${pass} passed, ${fail} failed (${label}: large inputs, growing buffers)`);
  return fail;
}

const engines = [
  ['uztranslit.wasm', await instantiate(readFileSync(new URL('./build/uztranslit.wasm', import.meta.url)))],
  ['uztranslit.engine.js', fromExports(await import('./build/uztranslit.engine.js'))]
];
let failures = 0;
for (const [label, U] of engines) failures += fixtureSuite(U, label);
for (const [label, U] of engines) failures += randomSuite(U, label);
for (const [label, U] of engines) failures += largeSuite(U, label);
process.exit(failures ? 1 : 0);
