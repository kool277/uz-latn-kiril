import { Encoding, isUnicode, sniffLegacy, utf16Guess } from './encoding';

/**
 * Plan for converting one large plain-text file on several workers: the bytes are cut right after line
 * feeds (or spaces), which never occur inside a multi-byte character, and no conversion rule looks across
 * whitespace — so the pieces convert independently and their outputs simply concatenate.
 */
export interface TextPlan {
  encoding: Encoding;
  /** bytes of the input byte-order mark */
  bomLength: number;
  outEncoding: Encoding;
  outBom: boolean;
  ranges: Array<[number, number]>;
}

export const PARALLEL_TEXT_MIN = 4 << 20;
const CHUNK = 2 << 20;

function isUtf8(bytes: Uint8Array, ranges: Array<[number, number]>): boolean {
  const d = new TextDecoder('utf-8', { fatal: true });
  try {
    for (const [s, e] of ranges) d.decode(bytes.subarray(s, e));
    return true;
  } catch {
    return false;
  }
}

function cut(bytes: Uint8Array, start: number, unit: 1 | 2, le: boolean, chunk: number): Array<[number, number]> {
  const out: Array<[number, number]> = [];
  const n = bytes.length;
  const isAt = (i: number, b: number) => (unit === 1 ? bytes[i] === b : le ? bytes[i] === b && bytes[i + 1] === 0 : bytes[i] === 0 && bytes[i + 1] === b);
  let pos = start;
  while (pos < n) {
    let end = Math.min(n, pos + chunk);
    if (end < n) {
      end -= (end - start) % unit;
      let k = end;
      while (k > pos + (chunk >> 1) && !isAt(k - unit, 0x0a)) k -= unit;
      if (k <= pos + (chunk >> 1)) { // no line feed: settle for a space, else extend to the next whitespace
        k = end;
        while (k > pos && !isAt(k - unit, 0x20)) k -= unit;
        if (k <= pos) {
          k = end;
          while (k < n && !isAt(k - unit, 0x0a) && !isAt(k - unit, 0x20)) k += unit;
        }
      }
      end = k;
    }
    out.push([pos, end]);
    pos = end;
  }
  return out;
}

export function planTextFile(bytes: Uint8Array, chunk = CHUNK): TextPlan {
  let encoding: Encoding;
  let bomLength = 0;
  if (bytes[0] === 0xef && bytes[1] === 0xbb && bytes[2] === 0xbf) { encoding = 'utf-8'; bomLength = 3; }
  else if (bytes[0] === 0xff && bytes[1] === 0xfe) { encoding = 'utf-16le'; bomLength = 2; }
  else if (bytes[0] === 0xfe && bytes[1] === 0xff) { encoding = 'utf-16be'; bomLength = 2; }
  else encoding = utf16Guess(bytes) ?? 'utf-8';
  const unit = encoding === 'utf-8' ? 1 : 2;
  const ranges = cut(bytes, bomLength, unit, encoding !== 'utf-16be', chunk);
  if (encoding === 'utf-8' && !bomLength && !isUtf8(bytes, ranges)) encoding = sniffLegacy(bytes.subarray(0, 1 << 16));
  const unicode = isUnicode(encoding);
  return { encoding, bomLength, outEncoding: unicode ? encoding : 'utf-8', outBom: unicode ? bomLength > 0 : true, ranges };
}
