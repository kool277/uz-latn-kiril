/**
 * Text encodings of plain-text inputs. Unicode inputs keep their encoding and byte-order mark; legacy
 * 8-bit inputs (Windows-1251, KOI8-R, DOS 866, Windows-1254/1252) are written back as UTF-8, because the
 * converted text needs letters those code pages do not have (ʻ ʼ in Latin, қ ғ ҳ in Cyrillic).
 */

export type Encoding = 'utf-8' | 'utf-16le' | 'utf-16be' | 'windows-1251' | 'koi8-r' | 'ibm866' | 'windows-1254' | 'windows-1252';

export interface Decoded {
  text: string;
  encoding: Encoding;
  bom: boolean;
}

const LEGACY: Encoding[] = ['windows-1251', 'koi8-r', 'ibm866', 'windows-1254', 'windows-1252'];

function isLowerCyr(c: number): boolean {
  return (c >= 0x430 && c <= 0x44f) || c === 0x451 || c === 0x45e || c === 0x49b || c === 0x493 || c === 0x4b3;
}
function isUpperCyr(c: number): boolean {
  return (c >= 0x410 && c <= 0x42f) || c === 0x401 || c === 0x40e || c === 0x49a || c === 0x492 || c === 0x4b2;
}
const NEW_LETTERS = new Set([0xf6, 0x11f, 0x15f, 0xe7, 0xd6, 0x11e, 0x15e, 0xc7]);

/** How plausible a decoding is as Uzbek (or Russian) text. */
function plausibility(s: string): number {
  let score = 0;
  let prev = 0x20;
  for (let i = 0; i < s.length; i++) {
    const c = s.charCodeAt(i);
    if (isLowerCyr(c)) score += 2;
    else if (isUpperCyr(c)) score += isLowerCyr(prev) ? -3 : 1;
    else if (NEW_LETTERS.has(c)) score += 2;
    else if ((c >= 0x80 && c < 0xa0) || c === 0xfffd) score -= 5;
    else if (c >= 0xa0 && c <= 0x24f) score -= 1;
    else if (c >= 0x2500 && c <= 0x259f) score -= 2; // box drawing: DOS code page misread
    prev = c;
  }
  return score;
}

/** UTF-16 without a byte-order mark: zero bytes at every other position. */
export function utf16Guess(b: Uint8Array): Encoding | null {
  const n = Math.min(b.length, 4096) & ~1;
  if (n < 4) return null;
  let evenZero = 0, oddZero = 0;
  for (let i = 0; i < n; i += 2) {
    if (b[i] === 0) evenZero++;
    if (b[i + 1] === 0) oddZero++;
  }
  const half = n / 2;
  if (oddZero > half * 0.3 && evenZero < half * 0.05) return 'utf-16le';
  if (evenZero > half * 0.3 && oddZero < half * 0.05) return 'utf-16be';
  return null;
}

export function decodeText(bytes: Uint8Array, declared?: string | null): Decoded {
  if (bytes.length >= 3 && bytes[0] === 0xef && bytes[1] === 0xbb && bytes[2] === 0xbf) {
    return { text: new TextDecoder('utf-8', { ignoreBOM: true }).decode(bytes.subarray(3)), encoding: 'utf-8', bom: true };
  }
  if (bytes.length >= 2 && bytes[0] === 0xff && bytes[1] === 0xfe) {
    return { text: new TextDecoder('utf-16le', { ignoreBOM: true }).decode(bytes.subarray(2)), encoding: 'utf-16le', bom: true };
  }
  if (bytes.length >= 2 && bytes[0] === 0xfe && bytes[1] === 0xff) {
    return { text: new TextDecoder('utf-16be', { ignoreBOM: true }).decode(bytes.subarray(2)), encoding: 'utf-16be', bom: true };
  }
  const u16 = utf16Guess(bytes);
  if (u16) return { text: new TextDecoder(u16, { ignoreBOM: true }).decode(bytes), encoding: u16, bom: false };
  try {
    return { text: new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(bytes), encoding: 'utf-8', bom: false };
  } catch {
    // not UTF-8: a legacy code page
  }
  const label = declared ? normaliseLabel(declared) : null;
  if (label && label !== 'utf-8') {
    return { text: new TextDecoder(label, { ignoreBOM: true }).decode(bytes), encoding: label, bom: false };
  }
  const best = sniffLegacy(bytes.subarray(0, 1 << 16));
  return { text: new TextDecoder(best, { ignoreBOM: true }).decode(bytes), encoding: best, bom: false };
}

/** The legacy code page under which a (non-UTF-8) sample reads most like Uzbek or Russian text. */
export function sniffLegacy(sample: Uint8Array): Encoding {
  let best: Encoding = 'windows-1251', bestScore = -Infinity;
  for (const enc of LEGACY) {
    const s = plausibility(new TextDecoder(enc).decode(sample));
    if (s > bestScore) { bestScore = s; best = enc; }
  }
  return best;
}

/** Maps a charset label (from an XML declaration or an HTML meta tag) to one we decode, or null. */
export function normaliseLabel(label: string): Encoding | null {
  const l = label.trim().toLowerCase().replace(/_/g, '-');
  if (l === 'utf-8' || l === 'utf8') return 'utf-8';
  if (l === 'utf-16' || l === 'utf-16le') return 'utf-16le';
  if (l === 'utf-16be') return 'utf-16be';
  if (l === 'windows-1251' || l === 'cp1251' || l === 'x-cp1251') return 'windows-1251';
  if (l === 'koi8-r' || l === 'koi8r' || l === 'koi8-u') return 'koi8-r';
  if (l === 'ibm866' || l === 'cp866' || l === '866') return 'ibm866';
  if (l === 'windows-1254' || l === 'cp1254' || l === 'iso-8859-9' || l === 'latin5') return 'windows-1254';
  if (l === 'windows-1252' || l === 'cp1252' || l === 'iso-8859-1' || l === 'latin1' || l === 'us-ascii' || l === 'ascii') return 'windows-1252';
  return null;
}

export function isUnicode(e: Encoding): boolean {
  return e === 'utf-8' || e === 'utf-16le' || e === 'utf-16be';
}

export function encodeText(text: string, encoding: Encoding, bom: boolean): Uint8Array {
  if (encoding === 'utf-16le' || encoding === 'utf-16be') {
    const off = bom ? 2 : 0;
    const out = new Uint8Array(off + text.length * 2);
    const le = encoding === 'utf-16le';
    if (bom) { out[0] = le ? 0xff : 0xfe; out[1] = le ? 0xfe : 0xff; }
    for (let i = 0; i < text.length; i++) {
      const c = text.charCodeAt(i);
      out[off + 2 * i] = le ? c & 0xff : c >> 8;
      out[off + 2 * i + 1] = le ? c >> 8 : c & 0xff;
    }
    return out;
  }
  const body = new TextEncoder().encode(text);
  if (!bom) return body;
  const out = new Uint8Array(body.length + 3);
  out.set([0xef, 0xbb, 0xbf]);
  out.set(body, 3);
  return out;
}
