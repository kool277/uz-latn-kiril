import { uzLangTag, uzScriptCode } from './langtag';
import { applyEdits, decodeXml, Edit, escapeXmlAttr, escapeXmlText, Paragraph, Segment } from './text-model';
import { Script } from './types';

/**
 * A small, non-validating XML scanner and a rule-driven text collector. It never expands DTD entities
 * (no XXE, no "billion laughs") and leaves every byte it does not rewrite exactly as it was.
 */

export interface XmlHandler {
  /** [start, end) covers the whole tag; the name ends at nameEnd */
  start(name: string, start: number, nameEnd: number, end: number, selfClosing: boolean): void;
  end(name: string, start: number, end: number): void;
  text(start: number, end: number): void;
  cdata(start: number, end: number): void;
}

function isNameEnd(c: number): boolean {
  return c === 0x20 || c === 0x09 || c === 0x0a || c === 0x0d || c === 0x2f || c === 0x3e;
}

function skipDeclaration(src: string, i: number): number {
  // <!DOCTYPE …> with an optional internal subset […]
  let depth = 0, q = 0;
  for (let k = i + 2; k < src.length; k++) {
    const c = src.charCodeAt(k);
    if (q) { if (c === q) q = 0; continue; }
    if (c === 0x22 || c === 0x27) q = c;
    else if (c === 0x5b) depth++;
    else if (c === 0x5d) depth--;
    else if (c === 0x3e && depth <= 0) return k + 1;
  }
  return src.length;
}

export function scanXml(src: string, h: XmlHandler): void {
  const n = src.length;
  let i = 0;
  while (i < n) {
    const lt = src.indexOf('<', i);
    if (lt < 0) { h.text(i, n); return; }
    if (lt > i) h.text(i, lt);
    const c = src.charCodeAt(lt + 1);
    if (c === 0x21) { // !
      if (src.startsWith('!--', lt + 1)) {
        const e = src.indexOf('-->', lt + 4);
        i = e < 0 ? n : e + 3;
      } else if (src.startsWith('![CDATA[', lt + 1)) {
        const e = src.indexOf(']]>', lt + 9);
        h.cdata(lt + 9, e < 0 ? n : e);
        i = e < 0 ? n : e + 3;
      } else i = skipDeclaration(src, lt);
      continue;
    }
    if (c === 0x3f) { // ?
      const e = src.indexOf('?>', lt + 2);
      i = e < 0 ? n : e + 2;
      continue;
    }
    if (c === 0x2f) { // /
      const e = src.indexOf('>', lt + 2);
      const end = e < 0 ? n : e + 1;
      h.end(src.slice(lt + 2, e < 0 ? n : e).trim(), lt, end);
      i = end;
      continue;
    }
    let j = lt + 1;
    while (j < n && !isNameEnd(src.charCodeAt(j))) j++;
    let k = j, q = 0;
    for (; k < n; k++) {
      const d = src.charCodeAt(k);
      if (q) { if (d === q) q = 0; }
      else if (d === 0x22 || d === 0x27) q = d;
      else if (d === 0x3e) break;
    }
    const end = k < n ? k + 1 : n;
    h.start(src.slice(lt + 1, j), lt, j, end, src.charCodeAt(k - 1) === 0x2f);
    i = end;
  }
}

export interface Attr {
  name: string;
  /** raw value range (inside the quotes) */
  start: number;
  end: number;
  quote: string;
}

const ATTR_RE = /([^\s=/>]+)\s*=\s*("([^"]*)"|'([^']*)')/g;

export function parseAttrs(src: string, from: number, to: number): Attr[] {
  const out: Attr[] = [];
  const tag = src.slice(from, to);
  ATTR_RE.lastIndex = 0;
  let m: RegExpExecArray | null;
  while ((m = ATTR_RE.exec(tag))) {
    const valueStart = from + m.index + m[0].length - m[2].length + 1;
    out.push({ name: m[1], start: valueStart, end: valueStart + m[2].length - 2, quote: m[2][0] });
  }
  return out;
}

// ---------------------------------------------------------------- rules

/** Element kinds (bit flags). */
export const PARA = 1; // starts a paragraph context; nested ones stack (text boxes, footnotes, comments)
export const ALLTEXT = 2; // with PARA: every text node inside belongs to the paragraph (ODF, HTML-like)
export const TEXT = 4; // text-run element whose content belongs to the open paragraph (w:t, a:t, t)
export const SKIP = 8; // the whole subtree is left alone (field codes, phonetic runs, binaries …)
export const SEP = 16; // stands for a separator character inside the paragraph (tab, break, object)
export const SCOPE = 32; // enables IN_SCOPE text elements inside it (chart string caches)
export const IN_SCOPE = 64; // TEXT only inside a SCOPE element
export const LANGTEXT = 128; // text content is a language tag (EPUB dc:language)
export const PRESERVE = 256; // TEXT whose start tag needs xml:space="preserve" for edge whitespace (w:t, t)

export interface ElementRule {
  kind: number;
  sep?: string;
  /** attributes (qualified as {uri}local or local) whose values are converted, each as its own paragraph */
  attrs?: string[];
  /** attributes holding a BCP 47 language tag */
  lang?: string[];
  /** ODF: [language attr, script attr] — the script code is switched when the language is Uzbek */
  script?: [string, string];
}

/** Element rules by namespace URI, then local name ('' namespace = no namespace). */
export type XmlRules = Record<string, Record<string, ElementRule>>;

export interface XmlProfile {
  rules: XmlRules;
  /** generic XML: every element is a paragraph of its own text */
  everyElement?: boolean;
  /** generic XML: local names whose subtree is skipped (script, style) */
  skipLocal?: string[];
}

export const XML_NS = 'http://www.w3.org/XML/1998/namespace';

interface Compiled {
  elements: Map<string, ElementRule>;
  attrs: Map<ElementRule, Set<string>>;
  lang: Map<ElementRule, Set<string>>;
  script: Map<ElementRule, [string, string]>;
}

interface Frame {
  name: string;
  rule: ElementRule | undefined;
  para: boolean; // pushed a paragraph
  text: boolean; // TEXT element
  skip: boolean;
  scope: boolean;
  ns: boolean; // pushed a namespace scope
  preserve?: { insertAt: number; has: boolean; done: boolean };
}

export interface XmlSegment extends Segment {
  kind: 'text' | 'cdata' | 'attr';
  quote?: string;
  owner?: { insertAt: number; has: boolean; done: boolean };
}

export interface XmlCollected {
  src: string;
  paras: Paragraph<XmlSegment>[];
  langEdits: Array<{ start: number; end: number; value: string; kind: 'tag' | 'script' }>;
}

function qualify(bindings: Map<string, string>, uriLocal: string): string[] {
  // '{uri}local' → every qualified name that resolves to it under the current bindings
  if (!uriLocal.startsWith('{')) return [uriLocal];
  const close = uriLocal.indexOf('}');
  const uri = uriLocal.slice(1, close), local = uriLocal.slice(close + 1);
  const names: string[] = [];
  for (const [prefix, u] of bindings) if (u === uri && prefix !== '') names.push(prefix + ':' + local);
  if (uri === XML_NS) names.push('xml:' + local);
  return names;
}

function compile(profile: XmlProfile, bindings: Map<string, string>): Compiled {
  const elements = new Map<string, ElementRule>();
  const attrs = new Map<ElementRule, Set<string>>();
  const lang = new Map<ElementRule, Set<string>>();
  const script = new Map<ElementRule, [string, string]>();
  for (const [prefix, uri] of bindings) {
    const byLocal = profile.rules[uri];
    if (!byLocal) continue;
    for (const local in byLocal) {
      const rule = byLocal[local];
      elements.set(prefix ? prefix + ':' + local : local, rule);
      if (rule.attrs) attrs.set(rule, new Set(rule.attrs.flatMap(a => qualify(bindings, a))));
      if (rule.lang) lang.set(rule, new Set(rule.lang.flatMap(a => qualify(bindings, a))));
      if (rule.script) {
        const [l, s] = rule.script.map(a => qualify(bindings, a)[0] ?? '');
        script.set(rule, [l, s]);
      }
    }
  }
  return { elements, attrs, lang, script };
}

const XMLNS_RE = /\sxmlns(?::([^\s=/>]+))?\s*=\s*("([^"]*)"|'([^']*)')/g;

/** Walks the document and gathers the paragraphs to convert. */
export function collectXml(src: string, profile: XmlProfile): XmlCollected {
  const paras: Paragraph<XmlSegment>[] = [];
  const langEdits: XmlCollected['langEdits'] = [];
  let bindings = new Map<string, string>([['', ''], ['xml', XML_NS]]);
  const nsStack: Array<{ bindings: Map<string, string>; compiled: Compiled }> = [];
  let compiled = compile(profile, bindings);
  const frames: Frame[] = [];
  const paraStack: Paragraph<XmlSegment>[] = [];
  let skipDepth = 0, textDepth = 0, scopeDepth = 0;
  let langText: { start: number; end: number } | null = null;
  let langTextDepth = -1;
  const skipLocal = new Set(profile.skipLocal ?? []);
  let owner: Frame['preserve'] | undefined;

  const closePara = () => {
    const p = paraStack.pop();
    if (p && p.segments > 0) paras.push(p);
  };

  const addText = (start: number, end: number, cdata: boolean) => {
    if (skipDepth > 0 || start >= end) return;
    if (langTextDepth >= 0) { langText = { start, end }; return; }
    const p = paraStack[paraStack.length - 1];
    if (!p || (textDepth === 0 && !allText.has(p))) return;
    const raw = src.slice(start, end);
    p.add({ start, end, text: cdata ? raw : decodeXml(raw), kind: cdata ? 'cdata' : 'text', owner: textDepth > 0 ? owner : undefined });
  };
  const allText = new WeakSet<Paragraph<XmlSegment>>();

  scanXml(src, {
    start(name, start, nameEnd, end, selfClosing) {
      const tagEnd = selfClosing ? end - 2 : end - 1;
      // namespace declarations
      let ns = false;
      const tagSrc = src.slice(nameEnd, tagEnd);
      if (tagSrc.includes('xmlns')) {
        let next: Map<string, string> | null = null;
        const decl = ' ' + tagSrc;
        XMLNS_RE.lastIndex = 0;
        let m: RegExpExecArray | null;
        while ((m = XMLNS_RE.exec(decl))) {
          next ??= new Map(bindings);
          next.set(m[1] ?? '', decodeXml(m[3] ?? m[4] ?? ''));
        }
        if (next) {
          nsStack.push({ bindings, compiled });
          bindings = next;
          compiled = compile(profile, bindings);
          ns = true;
        }
      }
      const local = name.includes(':') ? name.slice(name.indexOf(':') + 1) : name;
      let rule = compiled.elements.get(name);
      if (!rule && profile.everyElement) rule = skipLocal.has(local) ? { kind: SKIP } : { kind: PARA | ALLTEXT };
      const kind = rule?.kind ?? 0;
      const frame: Frame = { name, rule, para: false, text: false, skip: false, scope: false, ns };

      if (skipDepth === 0 && rule) {
        if (kind & SKIP) { frame.skip = true; skipDepth++; }
        else {
          if (rule.attrs || rule.lang || rule.script) {
            const attrs = parseAttrs(src, nameEnd, tagEnd);
            const conv = compiled.attrs.get(rule), lang = compiled.lang.get(rule), script = compiled.script.get(rule);
            let uzLanguage = false;
            if (script) uzLanguage = attrs.some(a => a.name === script[0] && src.slice(a.start, a.end).toLowerCase() === 'uz');
            for (const a of attrs) {
              if (conv?.has(a.name) && a.end > a.start) {
                const p = new Paragraph<XmlSegment>();
                p.add({ start: a.start, end: a.end, text: decodeXml(src.slice(a.start, a.end)), kind: 'attr', quote: a.quote });
                paras.push(p);
              }
              if (lang?.has(a.name)) langEdits.push({ start: a.start, end: a.end, value: src.slice(a.start, a.end), kind: 'tag' });
              if (uzLanguage && script && a.name === script[1]) langEdits.push({ start: a.start, end: a.end, value: src.slice(a.start, a.end), kind: 'script' });
            }
          }
          if (kind & SEP) paraStack[paraStack.length - 1]?.sep(rule.sep ?? '\ufffc');
          if (kind & SCOPE) { frame.scope = true; scopeDepth++; }
          if (kind & LANGTEXT && !selfClosing) langTextDepth = frames.length;
          if (kind & PARA) {
            const p = new Paragraph<XmlSegment>();
            if (kind & ALLTEXT) allText.add(p);
            paraStack.push(p);
            frame.para = true;
          }
          if (kind & TEXT && (!(kind & IN_SCOPE) || scopeDepth > 0)) {
            frame.text = true;
            textDepth++;
            if (!paraStack.length) { // a text element outside any paragraph is a paragraph of its own
              paraStack.push(new Paragraph<XmlSegment>());
              frame.para = true;
            }
            if (kind & PRESERVE) {
              frame.preserve = { insertAt: tagEnd, has: /xml:space\s*=\s*["']preserve["']/.test(tagSrc), done: false };
            }
            owner = frame.preserve;
          }
        }
      }
      if (selfClosing) {
        endFrame(frame);
      } else frames.push(frame);
    },
    end(name) {
      // tolerate unbalanced markup: unwind to the matching element
      for (let k = frames.length - 1; k >= 0; k--) {
        if (frames[k].name === name) {
          while (frames.length > k) endFrame(frames.pop()!);
          return;
        }
      }
    },
    text(start, end) { addText(start, end, false); },
    cdata(start, end) { addText(start, end, true); }
  });
  while (frames.length) endFrame(frames.pop()!);
  while (paraStack.length) closePara();
  return { src, paras, langEdits };

  function endFrame(f: Frame) {
    if (f.skip) skipDepth--;
    if (f.text) { textDepth--; owner = undefined; }
    if (f.scope) scopeDepth--;
    if (langTextDepth === frames.length && f.rule && (f.rule.kind & LANGTEXT)) {
      if (langText) langEdits.push({ ...langText, value: src.slice(langText.start, langText.end), kind: 'tag' });
      langText = null;
      langTextDepth = -1;
    }
    if (f.para) closePara();
    if (f.ns) {
      const prev = nsStack.pop()!;
      bindings = prev.bindings;
      compiled = prev.compiled;
    }
  }
}

/** Writes the converted segments (and language-tag changes) back into the document. */
export function writeXml(c: XmlCollected, to: Script): { xml: string; changed: boolean } {
  const edits: Edit[] = [];
  for (const p of c.paras) {
    for (const it of p.items) {
      if (typeof it === 'string' || it.out === undefined || it.out === it.text) continue;
      const text = it.kind === 'attr' ? escapeXmlAttr(it.out, it.quote ?? '"') : it.kind === 'cdata' ? it.out : escapeXmlText(it.out);
      edits.push({ start: it.start, end: it.end, text });
      const o = it.owner;
      if (o && !o.has && !o.done && /^\s|\s$/.test(it.out)) {
        o.done = true;
        edits.push({ start: o.insertAt, end: o.insertAt, text: ' xml:space="preserve"' });
      }
    }
  }
  for (const l of c.langEdits) {
    const v = l.kind === 'tag' ? uzLangTag(l.value, to) : uzScriptCode(l.value, to);
    if (v !== l.value) edits.push({ start: l.start, end: l.end, text: v });
  }
  return { xml: applyEdits(c.src, edits), changed: edits.length > 0 };
}
