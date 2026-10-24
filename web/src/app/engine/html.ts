import { uzLangTag } from './langtag';
import { applyEdits, Edit, Paragraph, Segment, SEP_OBJECT } from './text-model';
import { Script } from './types';

/**
 * HTML / XHTML text collector. Visible text is grouped into paragraphs at block boundaries (inline markup
 * such as <b> or <a> does not split a word), selected attributes are converted on their own, and
 * script/style/code, translate="no" content and URLs stay untouched. The markup is never re-serialised:
 * only the rewritten text ranges change.
 */

const INLINE = new Set(('a abbr acronym b bdi bdo big cite data del dfn em font i ins label mark nobr q rb rp rt rtc ruby s small span ' +
  'strike strong sub sup time tt u wbr').split(' '));
const RAW_TEXT = new Set(['script', 'style', 'xmp', 'iframe', 'noembed', 'noframes', 'plaintext']);
const SKIP = new Set(['script', 'style', 'template', 'code', 'kbd', 'samp', 'var', 'svg', 'math', 'xmp', 'iframe', 'noembed', 'noframes', 'plaintext']);
const VOID = new Set('area base br col embed hr img input link meta param source track wbr'.split(' '));
const OPTIONAL_END = new Set('p li dt dd tr td th thead tbody tfoot option optgroup rb rt rtc rp colgroup caption'.split(' '));
const TEXT_ATTRS = new Set(['title', 'alt', 'placeholder', 'aria-label', 'aria-description', 'aria-roledescription', 'aria-valuetext']);
const META_NAMES = new Set(['description', 'keywords', 'og:title', 'og:description', 'og:site_name', 'twitter:title',
  'twitter:description', 'application-name', 'apple-mobile-web-app-title', 'dc.title', 'dc.description', 'dc.subject']);

// named character references that matter for Uzbek text; anything else stays an opaque reference
const ENTITIES: Record<string, string> = {
  nbsp: '\u00a0', amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", shy: '\u00ad', laquo: '«', raquo: '»',
  lsquo: '‘', rsquo: '’', sbquo: '‚', ldquo: '“', rdquo: '”', bdquo: '„', prime: '′', Prime: '″', acute: '´', grave: '`',
  ndash: '–', mdash: '—', hellip: '…', middot: '·', bull: '•', deg: '°', copy: '©', reg: '®', trade: '™', sect: '§',
  para: '¶', plusmn: '±', times: '×', divide: '÷', euro: '€', ensp: '\u2002', emsp: '\u2003', thinsp: '\u2009',
  zwnj: '\u200c', zwj: '\u200d', lrm: '\u200e', rlm: '\u200f', numero: '№', minus: '−', larr: '←', rarr: '→',
  Ouml: 'Ö', ouml: 'ö', Ccedil: 'Ç', ccedil: 'ç', Otilde: 'Õ', otilde: 'õ'
};

export interface HtmlSegment extends Segment {
  quote?: string; // attribute value: '"', "'" or '' (unquoted)
}

export interface HtmlCollected {
  src: string;
  paras: Paragraph<HtmlSegment>[];
  edits: Array<{ start: number; end: number; value: string; kind: 'lang' | 'charset' }>;
  xhtml: boolean;
}

interface HtmlAttr {
  name: string;
  start: number;
  end: number;
  quote: string;
}

const ATTR_RE = /([^\s"'>/=]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+)))?/g;

function parseAttrs(src: string, from: number, to: number): HtmlAttr[] {
  const out: HtmlAttr[] = [];
  const tag = src.slice(from, to);
  ATTR_RE.lastIndex = 0;
  let m: RegExpExecArray | null;
  while ((m = ATTR_RE.exec(tag))) {
    const v = m[2] ?? m[3] ?? m[4];
    if (v === undefined) continue;
    const quote = m[2] !== undefined ? '"' : m[3] !== undefined ? "'" : '';
    const valueEnd = from + m.index + m[0].length - (quote ? 1 : 0);
    out.push({ name: m[1].toLowerCase(), start: valueEnd - v.length, end: valueEnd, quote });
  }
  return out;
}

/** Splits raw HTML text into decoded pieces; unknown character references become separators. */
function textPieces(src: string, start: number, end: number, p: Paragraph<HtmlSegment>): void {
  let pieceStart = start;
  let decoded = '';
  let i = start;
  const flush = (to: number) => {
    if (to > pieceStart) p.add({ start: pieceStart, end: to, text: decoded });
    decoded = '';
  };
  while (i < end) {
    const amp = src.indexOf('&', i);
    if (amp < 0 || amp >= end) { decoded += src.slice(i, end); break; }
    decoded += src.slice(i, amp);
    const m = /^&(?:#[xX]([0-9a-fA-F]{1,6})|#([0-9]{1,7})|([A-Za-z][A-Za-z0-9]{1,31}));/.exec(src.slice(amp, Math.min(end, amp + 40)));
    if (!m) { decoded += '&'; i = amp + 1; continue; }
    let ch: string | undefined;
    if (m[3] !== undefined) ch = ENTITIES[m[3]];
    else {
      const cp = m[1] !== undefined ? parseInt(m[1], 16) : parseInt(m[2], 10);
      if (cp > 0 && cp <= 0x10ffff && !(cp >= 0xd800 && cp <= 0xdfff)) ch = String.fromCodePoint(cp);
    }
    if (ch === undefined) { // an entity we do not know: keep it, as a boundary
      flush(amp);
      p.sep(SEP_OBJECT);
      pieceStart = amp + m[0].length;
    } else decoded += ch;
    i = amp + m[0].length;
  }
  flush(end);
}

/** Index of the `</name` that ends a raw-text element (case-insensitive), or the end of the document. */
function closingTag(src: string, name: string, from: number): number {
  const re = new RegExp('</' + name + '[\\s>/]', 'ig');
  re.lastIndex = from;
  const m = re.exec(src);
  return m ? m.index : src.length;
}

function attrText(raw: string): string {
  const p = new Paragraph<HtmlSegment>();
  textPieces(raw, 0, raw.length, p);
  return p.items.map(it => (typeof it === 'string' ? '' : it.text)).join('');
}

export function collectHtml(src: string, opts: { xhtml: boolean; legacyCharset: boolean }): HtmlCollected {
  const paras: Paragraph<HtmlSegment>[] = [];
  const edits: HtmlCollected['edits'] = [];
  const open: { p: Paragraph<HtmlSegment> | null } = { p: null };
  let skipName = '', skipDepth = 0;
  const closePara = () => {
    if (open.p && open.p.segments > 0) paras.push(open.p);
    open.p = null;
  };
  const para = () => (open.p ??= new Paragraph<HtmlSegment>());
  const n = src.length;
  let i = 0;
  while (i < n) {
    const lt = src.indexOf('<', i);
    const textEnd = lt < 0 ? n : lt;
    if (textEnd > i && skipDepth === 0) textPieces(src, i, textEnd, para());
    if (lt < 0) break;
    i = lt;
    if (src.startsWith('<!--', lt)) { const e = src.indexOf('-->', lt + 4); i = e < 0 ? n : e + 3; continue; }
    if (src.startsWith('<![CDATA[', lt)) { const e = src.indexOf(']]>', lt + 9); i = e < 0 ? n : e + 3; continue; }
    const c1 = src.charCodeAt(lt + 1);
    if (c1 === 0x21 || c1 === 0x3f) { const e = src.indexOf('>', lt + 2); i = e < 0 ? n : e + 1; continue; } // <!DOCTYPE …>, <?…>
    const isEnd = c1 === 0x2f;
    const nameStart = lt + (isEnd ? 2 : 1);
    const first = src.charCodeAt(nameStart);
    if (!((first >= 0x41 && first <= 0x5a) || (first >= 0x61 && first <= 0x7a))) { // "a < b": just text
      if (skipDepth === 0) textPieces(src, lt, lt + 1, para());
      i = lt + 1;
      continue;
    }
    let j = nameStart;
    while (j < n && !/[\s/>]/.test(src[j])) j++;
    const name = src.slice(nameStart, j).toLowerCase();
    let k = j, q = 0;
    for (; k < n; k++) {
      const d = src.charCodeAt(k);
      if (q) { if (d === q) q = 0; }
      else if (d === 0x22 || d === 0x27) q = d;
      else if (d === 0x3e) break;
    }
    const tagEnd = k; // index of '>'
    i = k < n ? k + 1 : n;
    const selfClosing = src.charCodeAt(k - 1) === 0x2f;

    if (isEnd) {
      if (skipDepth > 0) {
        if (name === skipName && --skipDepth === 0) { skipName = ''; if (open.p) para().sep(SEP_OBJECT); }
        continue;
      }
      if (!INLINE.has(name)) closePara();
      continue;
    }
    if (skipDepth > 0) {
      if (name === skipName && !selfClosing && !VOID.has(name)) skipDepth++;
      continue;
    }
    const attrs = parseAttrs(src, j, selfClosing ? tagEnd - 1 : tagEnd);
    // attributes
    const get = (a: string) => attrs.find(x => x.name === a);
    for (const a of attrs) {
      let convert = TEXT_ATTRS.has(a.name) || (a.name === 'label' && /^(option|optgroup|track|menuitem)$/.test(name));
      if (a.name === 'value' && name === 'input') convert = /^(button|submit|reset)$/i.test(src.slice(get('type')?.start ?? 0, get('type')?.end ?? 0));
      if (a.name === 'content' && name === 'meta') {
        const key = get('name') ?? get('property');
        convert = !!key && META_NAMES.has(src.slice(key.start, key.end).toLowerCase());
      }
      if (convert && a.end > a.start) {
        const p = new Paragraph<HtmlSegment>();
        p.add({ start: a.start, end: a.end, text: attrText(src.slice(a.start, a.end)), quote: a.quote });
        paras.push(p);
      }
      if (a.name === 'lang' || a.name === 'xml:lang') edits.push({ start: a.start, end: a.end, value: src.slice(a.start, a.end), kind: 'lang' });
      if (opts.legacyCharset && name === 'meta' && (a.name === 'charset' || (a.name === 'content' && /charset=/i.test(src.slice(a.start, a.end))))) {
        edits.push({ start: a.start, end: a.end, value: src.slice(a.start, a.end), kind: 'charset' });
      }
    }
    const translateNo = /^no$/i.test(src.slice(get('translate')?.start ?? 0, get('translate')?.end ?? 0)) ||
      /(^|\s)notranslate(\s|$)/.test(src.slice(get('class')?.start ?? 0, get('class')?.end ?? 0));
    if (name === 'br') { para().sep('\n'); continue; }
    if (name === 'img' || name === 'input' || name === 'embed' || name === 'object') { if (open.p) para().sep(SEP_OBJECT); continue; }
    if (name === 'wbr') continue;
    if (!INLINE.has(name)) closePara();
    const skip = SKIP.has(name) || (translateNo && !OPTIONAL_END.has(name) && !VOID.has(name));
    if (skip && !selfClosing && !VOID.has(name)) {
      skipName = name;
      skipDepth = 1;
      if (open.p) para().sep(SEP_OBJECT);
      if (RAW_TEXT.has(name) && !opts.xhtml) { // raw text runs to the matching end tag
        i = closingTag(src, name, i);
      }
      continue;
    }
    if ((name === 'title' || name === 'textarea') && !selfClosing) { // escapable raw text: no tags inside
      const e = closingTag(src, name, i);
      const p = new Paragraph<HtmlSegment>();
      textPieces(src, i, e, p);
      if (p.segments) paras.push(p);
      i = e;
    }
  }
  closePara();
  return { src, paras, edits, xhtml: opts.xhtml };
}

function escapeHtmlText(s: string, xhtml: boolean): string {
  return s.replace(/[&<>\u00a0]/g, c => (c === '&' ? '&amp;' : c === '<' ? '&lt;' : c === '>' ? '&gt;' : xhtml ? '\u00a0' : '&nbsp;'));
}

function escapeHtmlAttr(s: string, quote: string): string {
  const q = quote || '"';
  return s.replace(/[&<>"']/g, c => (c === '&' ? '&amp;' : c === '<' ? '&lt;' : c === '>' ? '&gt;' : c === q ? (c === '"' ? '&quot;' : '&#39;') : c));
}

export function writeHtml(c: HtmlCollected, to: Script): { html: string; changed: boolean } {
  const edits: Edit[] = [];
  for (const p of c.paras) {
    for (const it of p.items) {
      if (typeof it === 'string' || it.out === undefined || it.out === it.text) continue;
      if (it.quote === undefined) edits.push({ start: it.start, end: it.end, text: escapeHtmlText(it.out, c.xhtml) });
      else if (it.quote === '') edits.push({ start: it.start, end: it.end, text: '"' + escapeHtmlAttr(it.out, '"') + '"' });
      else edits.push({ start: it.start, end: it.end, text: escapeHtmlAttr(it.out, it.quote) });
    }
  }
  for (const e of c.edits) {
    const v = e.kind === 'lang' ? uzLangTag(e.value, to) : e.value.replace(/^[\w-]+$/, 'utf-8').replace(/charset=[\w-]+/i, 'charset=utf-8');
    if (v !== e.value) edits.push({ start: e.start, end: e.end, text: v });
  }
  return { html: applyEdits(c.src, edits), changed: edits.length > 0 };
}
