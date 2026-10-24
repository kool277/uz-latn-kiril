/* Seeded random Uzbek-like text for differential tests: real words from the fixtures mixed with single letters of
 * all three scripts, every apostrophe variant, JavaScript whitespace (and look-alikes that are not whitespace in JS),
 * URL/e-mail/handle fragments and emoji. No lone surrogates: Swift strings cannot hold them (core/wasm/test.mjs
 * covers them for the JS and WebAssembly engines). */
import { readFileSync } from 'node:fs';

const fixtures = JSON.parse(readFileSync(new URL('../spec/fixtures.json', import.meta.url), 'utf8'));
const corpusWords = [];
for (const c of fixtures.cases) corpusWords.push(...c.in.split(/\s+/), ...c.out.split(/\s+/));

const TOKENS = [
  ...'абвгдеёжзийклмнопрстуфхцчшщъыьэюяўқғҳАБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯЎҚҒҲ',
  ...'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZöğşçōõÖĞŞÇŌÕ',
  ..."'ʻʼ‘’`´", ' ', ' ', ' ', '\n', '\t', '\u00a0', '\u2028', '\u3000', '\u0085', '\u001c', '\u200b',
  ...'.,;:!?-()"«»0123456789@/_#', 'http://', 'https://', 'www.', '.uz', 'mail@', '@user', '@шаҳар', 'HTTP://',
  '\u{1F600}', 'sh', 'SH', 'Sh', 'ch', "o'", "g'", "s'h", 'ts', 'tsiya', 'tsion', 'TSIYA', 'ye', 'yo', "yo'",
  'yu', 'ya', 'kompyuter', 'obyekt', 'SIRK', 'Abzats', 'yogurt', 'ofitser', 'ShAHAR', 'İ', 'ı', 'K', 'ß'
];

export const DIRECTIONS = [['cyr', 'lat'], ['cyr', 'new'], ['lat', 'cyr'], ['new', 'cyr'], ['lat', 'new'], ['new', 'lat'],
  ['auto', 'cyr'], ['auto', 'lat'], ['auto', 'new'], ['lat', 'lat']];

export function rng(seed) {
  let s = seed >>> 0;
  return () => { // mulberry32
    s = (s + 0x6D2B79F5) >>> 0;
    let t = s;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export function randomText(rnd) {
  const pick = a => a[Math.floor(rnd() * a.length)];
  const n = 1 + Math.floor(rnd() * 40);
  let s = '';
  for (let i = 0; i < n; i++) s += rnd() < 0.25 ? pick(corpusWords) + ' ' : pick(TOKENS);
  return s;
}

/** Options with every key present, mostly defaults. */
export function randomOptions(rnd) {
  const o = { okina: 'ʻ', tutuq: 'ʼ', dropHardSignAfterO: true, tsFinal: true, dictionary: true, skipUrls: true };
  if (rnd() < 0.3) { o.okina = "'"; o.tutuq = "'"; }
  if (rnd() < 0.05) { o.okina = ''; o.tutuq = ''; }
  for (const k of ['dropHardSignAfterO', 'tsFinal', 'dictionary', 'skipUrls']) if (rnd() < 0.25) o[k] = false;
  return o;
}
