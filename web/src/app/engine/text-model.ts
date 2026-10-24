import { ConvertOptions, Converter, Script } from './types';

/**
 * A piece of document text that may be rewritten: a text node, a CDATA section or an attribute value,
 * located by its raw source range. `text` is the decoded value, `out` the converted one.
 */
export interface Segment {
  start: number;
  end: number;
  text: string;
  out?: string;
}

/**
 * Text that is converted as one string: the segments of a paragraph (Word runs, HTML inline elements …)
 * plus separator characters standing for tabs, line breaks and inline objects. Converting the whole
 * paragraph keeps the context the rules depend on (casing of ШАҲАР, е/э, digraphs) across run boundaries;
 * the engine then hands every segment its share of the result, so each run keeps its formatting.
 */
export class Paragraph<S extends Segment = Segment> {
  readonly items: Array<S | string> = [];
  segments = 0;

  add(seg: S): void {
    this.items.push(seg);
    this.segments++;
  }

  sep(ch: string): void {
    this.items.push(ch);
  }
}

/** Characters the scanners treat as boundaries; used for tabs, breaks and inline objects. */
export const SEP_OBJECT = '\ufffc';

const BATCH = 1 << 20; // UTF-16 code units per engine call

/**
 * Converts every paragraph in place (fills seg.out). Paragraphs are joined with '\n' into large batches;
 * a line feed is whitespace and a non-letter, so no rule (casing, words, URL tokens) reaches across it
 * and the batch converts exactly like each paragraph on its own.
 */
export function convertParagraphs(engine: Converter, paras: Iterable<Paragraph>, from: Script, to: Script,
  options: ConvertOptions): { segments: number; changed: number } {
  let pieces: string[] = [];
  let targets: Array<Segment | null> = [];
  let len = 0, segments = 0, changed = 0;
  const flush = () => {
    if (pieces.length === 0) return;
    const r = engine.convertSegments(pieces, from, to, options).pieces;
    for (let i = 0; i < targets.length; i++) {
      const t = targets[i];
      if (t) {
        t.out = r[i];
        if (r[i] !== t.text) changed++;
      }
    }
    pieces = [];
    targets = [];
    len = 0;
  };
  for (const p of paras) {
    if (p.segments === 0) continue;
    for (const it of p.items) {
      if (typeof it === 'string') { pieces.push(it); targets.push(null); len += it.length; }
      else { pieces.push(it.text); targets.push(it); len += it.text.length; segments++; }
    }
    pieces.push('\n');
    targets.push(null);
    len++;
    if (len >= BATCH) flush();
  }
  flush();
  return { segments, changed };
}

/** Text of the paragraphs, for script detection (bounded). */
export function sampleText(paras: Iterable<Paragraph>, limit = 1 << 20): string {
  const parts: string[] = [];
  let len = 0;
  for (const p of paras) {
    for (const it of p.items) {
      if (typeof it === 'string') continue;
      parts.push(it.text);
      len += it.text.length;
    }
    parts.push('\n');
    if (len > limit) break;
  }
  return parts.join('');
}

export interface Edit {
  start: number;
  end: number;
  text: string;
}

/** Applies non-overlapping edits (any order) to src. */
export function applyEdits(src: string, edits: Edit[]): string {
  if (edits.length === 0) return src;
  edits.sort((a, b) => a.start - b.start || a.end - b.end);
  const out: string[] = [];
  let pos = 0;
  for (const e of edits) {
    if (e.start < pos) continue; // overlapping edit: keep the first one
    out.push(src.slice(pos, e.start), e.text);
    pos = e.end;
  }
  out.push(src.slice(pos));
  return out.join('');
}

export function escapeXmlText(s: string): string {
  return s.replace(/[&<>\r]/g, c => (c === '&' ? '&amp;' : c === '<' ? '&lt;' : c === '>' ? '&gt;' : '&#13;'));
}

export function escapeXmlAttr(s: string, quote: string): string {
  return s.replace(/[&<>"'\t\n\r]/g, c => {
    switch (c) {
      case '&': return '&amp;';
      case '<': return '&lt;';
      case '>': return '&gt;';
      case '\t': return '&#9;';
      case '\n': return '&#10;';
      case '\r': return '&#13;';
      default: return c === quote ? (c === '"' ? '&quot;' : '&apos;') : c;
    }
  });
}

const XML_ENTITY = /&(?:#[xX]([0-9a-fA-F]{1,6})|#([0-9]{1,7})|(lt|gt|amp|quot|apos));/g;
const NAMED: Record<string, string> = { lt: '<', gt: '>', amp: '&', quot: '"', apos: "'" };

/** Decodes the five XML entities and character references; anything else stays as written. */
export function decodeXml(s: string): string {
  if (s.indexOf('&') < 0) return s;
  return s.replace(XML_ENTITY, (m, hex: string, dec: string, name: string) => {
    if (name) return NAMED[name];
    const cp = hex ? parseInt(hex, 16) : parseInt(dec, 10);
    return cp > 0 && cp <= 0x10ffff && !(cp >= 0xd800 && cp <= 0xdfff) ? String.fromCodePoint(cp) : m;
  });
}
