import { decodeText, encodeText, isUnicode } from '../encoding';
import { collectHtml, HtmlCollected, writeHtml } from '../html';
import { Paragraph } from '../text-model';
import { ConversionError, FormatId, Script } from '../types';
import { ALLTEXT, LANGTEXT, PARA, SKIP, XmlProfile } from '../xml';
import { decodeXmlBytes, encodeXmlText, XmlText } from '../xmldoc';
import { ZipArchive, ZipEntry } from '../zip';
import { Prepared } from './prepared';
import { XmlPart } from './xml-package';

// ---------------------------------------------------------------- HTML

/** An HTML or XHTML document (a web page, or a chapter of an EPUB). */
export class HtmlPart {
  readonly collected: HtmlCollected;

  constructor(readonly source: XmlText, xhtml: boolean) {
    this.collected = collectHtml(source.text, { xhtml, legacyCharset: !isUnicode(source.encoding) });
  }

  get paras(): Paragraph[] {
    return this.collected.paras;
  }

  finish(to: Script): Uint8Array | null {
    const r = writeHtml(this.collected, to);
    if (!r.changed) return null;
    return isUnicode(this.source.encoding) ? encodeText(r.html, this.source.encoding, this.source.bom) : encodeXmlText({ ...this.source, text: r.html });
  }
}

function htmlCharset(bytes: Uint8Array): string | null {
  const head = new TextDecoder('latin1').decode(bytes.subarray(0, 2048));
  const m = /<meta[^>]+charset\s*=\s*["']?\s*([\w-]+)/i.exec(head) ?? /^<\?xml[^>]*?encoding\s*=\s*["']([^"']+)["']/.exec(head);
  return m ? m[1] : null;
}

export function prepareHtml(bytes: Uint8Array, xhtml: boolean): Prepared {
  const d = decodeText(bytes, htmlCharset(bytes));
  const part = new HtmlPart({ text: d.text, encoding: d.encoding, bom: d.bom }, xhtml);
  return {
    format: 'html',
    mime: xhtml ? 'application/xhtml+xml' : 'text/html',
    paras: part.paras,
    parts: 1,
    encoding: d.encoding,
    warnings: [],
    finish: to => part.finish(to)
  };
}

// ---------------------------------------------------------------- XML vocabularies

const FB2_LOCAL = {
  ...Object.fromEntries(['p', 'v', 'subtitle', 'text-author', 'td', 'th', 'book-title', 'first-name', 'middle-name', 'last-name',
    'nickname', 'book-name', 'publisher', 'city', 'keywords'].map(k => [k, { kind: PARA | ALLTEXT }])),
  ...Object.fromEntries(['binary', 'genre', 'lang', 'src-lang', 'date', 'id', 'version', 'program-used', 'email', 'home-page',
    'isbn', 'year', 'src-url', 'src-ocr', 'code'].map(k => [k, { kind: SKIP }])),
  sequence: { kind: 0, attrs: ['name'] }
};
export const FB2_PROFILE: XmlProfile = {
  rules: { 'http://www.gribuser.ru/xml/fictionbook/2.0': FB2_LOCAL, 'http://www.gribuser.ru/xml/fictionbook/2.1': FB2_LOCAL, '': FB2_LOCAL }
};

const SVG_LOCAL = { text: { kind: PARA | ALLTEXT }, title: { kind: PARA | ALLTEXT }, desc: { kind: PARA | ALLTEXT }, script: { kind: SKIP }, style: { kind: SKIP } };
export const SVG_PROFILE: XmlProfile = { rules: { 'http://www.w3.org/2000/svg': SVG_LOCAL, '': SVG_LOCAL } };

export const GENERIC_XML_PROFILE: XmlProfile = { rules: {}, everyElement: true, skipLocal: ['script', 'style'] };

export function prepareXml(bytes: Uint8Array, format: FormatId, profile: XmlProfile, mime: string): Prepared {
  const part = XmlPart.fromBytes(bytes, profile);
  return {
    format,
    mime,
    paras: part.paras,
    parts: 1,
    encoding: part.source.encoding,
    warnings: [],
    finish: to => part.finish(to)
  };
}

// ---------------------------------------------------------------- EPUB

const DC = 'http://purl.org/dc/elements/1.1/';
const OPF_PROFILE: XmlProfile = {
  rules: {
    [DC]: {
      title: { kind: PARA | ALLTEXT }, description: { kind: PARA | ALLTEXT }, subject: { kind: PARA | ALLTEXT },
      creator: { kind: PARA | ALLTEXT }, contributor: { kind: PARA | ALLTEXT }, publisher: { kind: PARA | ALLTEXT },
      language: { kind: LANGTEXT }
    }
  }
};
const NCX_PROFILE: XmlProfile = { rules: { 'http://www.daisy.org/z3986/2005/ncx/': { text: { kind: PARA | ALLTEXT } } } };

export function prepareEpub(zip: ZipArchive): Prepared {
  const enc = zip.get('META-INF/encryption.xml');
  if (enc) {
    // font obfuscation only ever covers fonts; an encrypted text document means DRM
    const refs = [...zip.text(enc).matchAll(/<(?:\w+:)?CipherReference[^>]*URI\s*=\s*["']([^"']+)["']/g)].map(m => m[1]);
    if (refs.some(r => /\.(x?html?|ncx|opf|xml)$/i.test(r))) throw new ConversionError('err.encrypted');
  }
  const parts: Array<{ entry: ZipEntry; part: { paras: Paragraph[]; finish(to: Script): Uint8Array | null } }> = [];
  for (const e of zip.entries) {
    if (e.name.startsWith('META-INF/') || e.name === 'mimetype') continue;
    if (/\.(xhtml|html|htm)$/i.test(e.name)) parts.push({ entry: e, part: new HtmlPart(decodeXmlBytes(zip.data(e)), true) });
    else if (/\.opf$/i.test(e.name)) parts.push({ entry: e, part: XmlPart.fromBytes(zip.data(e), OPF_PROFILE) });
    else if (/\.ncx$/i.test(e.name)) parts.push({ entry: e, part: XmlPart.fromBytes(zip.data(e), NCX_PROFILE) });
  }
  return {
    format: 'epub',
    mime: 'application/epub+zip',
    get paras() { return parts.flatMap(p => p.part.paras); },
    parts: parts.length,
    warnings: [],
    finish: to => {
      for (const p of parts) {
        const out = p.part.finish(to);
        if (out) zip.replace(p.entry, out);
      }
      return zip.changed ? zip.write() : null;
    }
  };
}
