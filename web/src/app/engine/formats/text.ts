import { decodeText, Decoded, encodeText, isUnicode } from '../encoding';
import { applyEdits, Edit, Paragraph, Segment, SEP_OBJECT } from '../text-model';
import { FormatId } from '../types';
import { Prepared } from './prepared';

/** Unicode inputs keep encoding and BOM; legacy code pages become UTF-8 with a BOM (Notepad, Excel). */
function encodeLike(d: Decoded, text: string, bomForLegacy = true): Uint8Array {
  return isUnicode(d.encoding) ? encodeText(text, d.encoding, d.bom) : encodeText(text, 'utf-8', bomForLegacy);
}

function writeSegments(src: string, paras: Paragraph[], escape: (s: string, seg: Segment) => string = s => s): string {
  const edits: Edit[] = [];
  for (const p of paras) {
    for (const it of p.items) {
      if (typeof it !== 'string' && it.out !== undefined && it.out !== it.text) edits.push({ start: it.start, end: it.end, text: escape(it.out, it) });
    }
  }
  return applyEdits(src, edits);
}

function textPrepared(format: FormatId, mime: string, d: Decoded, paras: Paragraph[], write: () => string, bomForLegacy = true): Prepared {
  return {
    format,
    mime,
    paras,
    parts: 1,
    encoding: d.encoding,
    warnings: [],
    finish: () => {
      const text = write();
      if (text === d.text) return null;
      return encodeLike(d, text, bomForLegacy);
    }
  };
}

// ---------------------------------------------------------------- plain text, CSV

const CHUNK = 1 << 18;

/**
 * Splits text into chunks that end right after a whitespace character. No rule of the engine looks across
 * whitespace (words, casing, URL tokens), so converting the chunks separately gives exactly the same text.
 */
export function chunkAtWhitespace(text: string, size = CHUNK): Array<[number, number]> {
  const out: Array<[number, number]> = [];
  let pos = 0;
  while (pos < text.length) {
    let end = Math.min(text.length, pos + size);
    if (end < text.length) {
      const nl = text.lastIndexOf('\n', end - 1);
      if (nl >= pos + (size >> 1)) end = nl + 1;
      else {
        let k = end;
        while (k > pos && !/\s/.test(text[k - 1])) k--;
        if (k > pos) end = k;
        else { // no whitespace in the window: extend to the next one
          k = end;
          while (k < text.length && !/\s/.test(text[k - 1])) k++;
          end = k;
        }
      }
    }
    out.push([pos, end]);
    pos = end;
  }
  return out;
}

export function preparePlain(bytes: Uint8Array, format: 'text' | 'csv', mime: string): Prepared {
  const d = decodeText(bytes);
  const paras = chunkAtWhitespace(d.text).map(([s, e]) => {
    const p = new Paragraph();
    p.add({ start: s, end: e, text: d.text.slice(s, e) });
    return p;
  });
  return textPrepared(format, mime, d, paras, () => paras.map(p => {
    const seg = p.items[0] as Segment;
    return seg.out ?? seg.text;
  }).join(''));
}

// ---------------------------------------------------------------- shared: a line with protected spans

const SPLIT_LINES = /\r\n|\n|\r/g;

function lines(text: string): Array<{ start: number; end: number }> {
  const out: Array<{ start: number; end: number }> = [];
  let pos = 0;
  SPLIT_LINES.lastIndex = 0;
  let m: RegExpExecArray | null;
  while ((m = SPLIT_LINES.exec(text))) {
    out.push({ start: pos, end: m.index });
    pos = m.index + m[0].length;
  }
  out.push({ start: pos, end: text.length });
  return out;
}

/**
 * Adds src[start, end) to the paragraph, leaving out the spans matched by `protect`. A protected span is
 * either transparent (markup between the letters of one word, e.g. <b>) or a separator (code, URLs).
 */
function addWithProtected(p: Paragraph, src: string, start: number, end: number, protect: RegExp,
  transparent: (m: RegExpExecArray) => boolean): void {
  const s = src.slice(start, end);
  protect.lastIndex = 0;
  let pos = 0;
  let m: RegExpExecArray | null;
  while ((m = protect.exec(s))) {
    if (m[0].length === 0) { protect.lastIndex++; continue; }
    if (m.index > pos) p.add({ start: start + pos, end: start + m.index, text: s.slice(pos, m.index) });
    if (!transparent(m)) p.sep(SEP_OBJECT);
    pos = m.index + m[0].length;
  }
  if (pos < s.length) p.add({ start: start + pos, end, text: s.slice(pos) });
}

// ---------------------------------------------------------------- Markdown

// inline code, link/image destinations, reference labels, footnotes, autolinks and raw HTML tags
const MD_INLINE = /(`+)[\s\S]*?\1|\]\([^)\s]*(?:\s+"[^"]*")?\)|\]\[[^\]]*\]|\[\^[^\]]*\]|<[A-Za-z/!][^>]*>|<(?:https?|mailto|ftp):[^>]*>/g;

export function prepareMarkdown(bytes: Uint8Array): Prepared {
  const d = decodeText(bytes);
  const src = d.text;
  const paras: Paragraph[] = [];
  const all = lines(src);
  let i = 0;
  // YAML/TOML front matter
  if (/^(---|\+\+\+)\s*$/.test(src.slice(all[0]?.start ?? 0, all[0]?.end ?? 0))) {
    const fence = src.slice(all[0].start, all[0].end).trim();
    for (i = 1; i < all.length && src.slice(all[i].start, all[i].end).trim() !== fence; i++);
    i = i < all.length ? i + 1 : 0; // unclosed: not front matter
  }
  let fence = '';
  let prevBlank = true, prevCode = false, inList = false;
  for (; i < all.length; i++) {
    const { start, end } = all[i];
    const line = src.slice(start, end);
    const fm = /^ {0,3}(`{3,}|~{3,})/.exec(line);
    if (fence) {
      if (fm && fm[1][0] === fence[0] && fm[1].length >= fence.length && line.trim() === fm[1]) fence = '';
      continue;
    }
    if (fm) { fence = fm[1]; continue; }
    const blank = line.trim() === '';
    if (/^ {0,3}([-*+]|\d{1,9}[.)])\s/.test(line)) inList = true;
    else if (!blank && !/^\s/.test(line)) inList = false;
    const indentedCode: boolean = /^( {4}|\t)/.test(line) && !blank && !inList && (prevBlank || prevCode);
    prevCode = indentedCode || (prevCode && blank);
    prevBlank = blank;
    if (indentedCode || blank) continue;
    if (/^ {0,3}\[[^\]]+\]:\s*\S/.test(line)) continue; // link reference definition
    const p = new Paragraph();
    addWithProtected(p, src, start, end, MD_INLINE, m => m[0].startsWith('<') && !/^<(https?|mailto|ftp):/.test(m[0]));
    if (p.segments) paras.push(p);
  }
  return textPrepared('markdown', 'text/markdown', d, paras, () => writeSegments(src, paras));
}

// ---------------------------------------------------------------- JSON (string values, never keys)

interface JsonSegment extends Segment {
  unicodeEscapes: boolean;
}

function decodeJsonString(raw: string): string {
  return raw.replace(/\\(?:u([0-9a-fA-F]{4})|(.))/g, (_m, hex: string, c: string) => {
    if (hex) return String.fromCharCode(parseInt(hex, 16));
    return ({ b: '\b', f: '\f', n: '\n', r: '\r', t: '\t' } as Record<string, string>)[c] ?? c;
  });
}

function encodeJsonString(s: string, unicodeEscapes: boolean): string {
  return s.replace(/[\u0000-\u001f"\\\u2028\u2029]|[^\x00-\x7f]/g, c => {
    switch (c) {
      case '"': return '\\"';
      case '\\': return '\\\\';
      case '\n': return '\\n';
      case '\r': return '\\r';
      case '\t': return '\\t';
      case '\b': return '\\b';
      case '\f': return '\\f';
    }
    const code = c.charCodeAt(0);
    if (code < 0x20 || code === 0x2028 || code === 0x2029 || unicodeEscapes) return '\\u' + code.toString(16).padStart(4, '0');
    return c;
  });
}

export function prepareJson(bytes: Uint8Array): Prepared {
  const d = decodeText(bytes);
  const src = d.text;
  const paras: Paragraph<JsonSegment>[] = [];
  const n = src.length;
  for (let i = 0; i < n; i++) {
    if (src.charCodeAt(i) !== 0x22) continue;
    let j = i + 1;
    while (j < n && src.charCodeAt(j) !== 0x22) j += src.charCodeAt(j) === 0x5c ? 2 : 1;
    let k = j + 1;
    while (k < n && /\s/.test(src[k])) k++;
    if (src[k] !== ':' && j > i + 1) { // a value, not an object key
      const raw = src.slice(i + 1, j);
      const p = new Paragraph<JsonSegment>();
      p.add({ start: i + 1, end: j, text: decodeJsonString(raw), unicodeEscapes: /\\u(?:00[89a-fA-F]|0[1-9a-fA-F]|[1-9a-fA-F])/.test(raw) });
      paras.push(p);
    }
    i = j;
  }
  return textPrepared('json', 'application/json', d, paras,
    () => writeSegments(src, paras, (s, seg) => encodeJsonString(s, (seg as JsonSegment).unicodeEscapes)), false);
}

// ---------------------------------------------------------------- subtitles

const SUB_TAGS = /<[^>]*>|\{[^}]*\}|&(?:[a-zA-Z]+|#\d+);/g;

export function prepareSrt(bytes: Uint8Array): Prepared {
  const d = decodeText(bytes);
  const src = d.text;
  const paras: Paragraph[] = [];
  let cue: Paragraph | null = null;
  for (const { start, end } of lines(src)) {
    const line = src.slice(start, end);
    if (line.trim() === '') { if (cue?.segments) paras.push(cue); cue = null; continue; }
    if (/-->/.test(line) || (!cue && /^\s*\d+\s*$/.test(line))) continue; // timing, cue number
    if (cue) cue.sep('\n');
    cue ??= new Paragraph();
    addWithProtected(cue, src, start, end, SUB_TAGS, () => true);
  }
  if (cue?.segments) paras.push(cue);
  return textPrepared('srt', 'application/x-subrip', d, paras, () => writeSegments(src, paras));
}

export function prepareVtt(bytes: Uint8Array): Prepared {
  const d = decodeText(bytes);
  const src = d.text;
  const paras: Paragraph[] = [];
  const all = lines(src);
  let block: 'header' | 'skip' | 'cue' | 'start' = 'header';
  let cue: Paragraph | null = null;
  for (let i = 0; i < all.length; i++) {
    const { start, end } = all[i];
    const line = src.slice(start, end);
    if (line.trim() === '') {
      if (cue?.segments) paras.push(cue);
      cue = null;
      block = 'start';
      continue;
    }
    if (block === 'header' || block === 'skip') continue;
    if (block === 'start') {
      if (/^(NOTE|STYLE|REGION)(\s|$)/.test(line)) { block = 'skip'; continue; }
      block = 'cue';
      if (!line.includes('-->')) continue; // cue identifier
    }
    if (line.includes('-->')) continue; // timing and cue settings
    if (cue) cue.sep('\n');
    cue ??= new Paragraph();
    addWithProtected(cue, src, start, end, SUB_TAGS, () => true);
  }
  if (cue?.segments) paras.push(cue);
  return textPrepared('vtt', 'text/vtt', d, paras, () => writeSegments(src, paras));
}

const ASS_TAGS = /\{[^}]*\}|\\[Nnh]/g;

export function prepareAss(bytes: Uint8Array): Prepared {
  const d = decodeText(bytes);
  const src = d.text;
  const paras: Paragraph[] = [];
  let section = '';
  let textField = 9; // ASS/SSA: Layer|Marked, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
  for (const { start, end } of lines(src)) {
    const line = src.slice(start, end);
    const sec = /^\s*\[(.+)\]\s*$/.exec(line);
    if (sec) { section = sec[1].toLowerCase(); continue; }
    if (section !== 'events') continue;
    const fmt = /^Format:\s*(.*)$/i.exec(line);
    if (fmt) {
      const idx = fmt[1].split(',').map(f => f.trim().toLowerCase()).indexOf('text');
      if (idx >= 0) textField = idx;
      continue;
    }
    const dlg = /^Dialogue:\s*/i.exec(line);
    if (!dlg) continue;
    let pos = start + dlg[0].length;
    for (let f = 0; f < textField; f++) {
      const comma = src.indexOf(',', pos);
      if (comma < 0 || comma >= end) { pos = -1; break; }
      pos = comma + 1;
    }
    if (pos < 0) continue;
    const p = new Paragraph();
    addWithProtected(p, src, pos, end, ASS_TAGS, m => m[0].startsWith('{'));
    if (p.segments) paras.push(p);
  }
  return textPrepared('ass', 'text/x-ssa', d, paras, () => writeSegments(src, paras));
}

