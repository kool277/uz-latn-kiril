import { prepareOdf, prepareFlatOdf, odfMime } from './formats/odf';
import { prepareOoxml, ooxmlKind } from './formats/ooxml';
import { prepareEpub, prepareHtml, prepareXml, FB2_PROFILE, GENERIC_XML_PROFILE, SVG_PROFILE } from './formats/markup';
import { PrepareContext, Prepared } from './formats/prepared';
import { isRtf, prepareRtf } from './formats/rtf';
import { prepareAss, prepareJson, prepareMarkdown, preparePlain, prepareSrt, prepareVtt } from './formats/text';
import { outputName } from './names';
import { convertParagraphs, sampleText } from './text-model';
import { ConversionError, Converter, DocumentJob, DocumentResult, FormatId, Script } from './types';
import { ZipArchive } from './zip';

const CFB = [0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1];

function ext(name: string): string {
  const m = /\.([^./\\]+)$/.exec(name.toLowerCase());
  return m ? m[1] : '';
}

function startsWith(b: Uint8Array, sig: number[]): boolean {
  return b.length >= sig.length && sig.every((v, i) => b[i] === v);
}

function looksBinary(b: Uint8Array): boolean {
  const n = Math.min(b.length, 8192);
  let zeros = 0;
  for (let i = 0; i < n; i++) if (b[i] === 0) zeros++;
  // UTF-16 text has many zeros at alternating positions; arbitrary binaries have them everywhere
  if (zeros === 0) return false;
  let even = 0;
  for (let i = 0; i < n; i += 2) if (b[i] === 0) even++;
  const odd = zeros - even;
  return !(even > n * 0.3 && odd < n * 0.02) && !(odd > n * 0.3 && even < n * 0.02);
}

/** Parses any supported document into paragraphs plus a writer. */
export function prepareDocument(bytes: Uint8Array, name: string, ctx: PrepareContext): Prepared {
  const e = ext(name);
  if (ZipArchive.isZip(bytes)) {
    const zip = ZipArchive.read(bytes);
    if (ooxmlKind(zip)) return prepareOoxml(zip, name, ctx, (b, n, c) => prepareDocument(b, n, c));
    if (odfMime(zip)) return prepareOdf(zip);
    const mt = zip.get('mimetype');
    if (mt && new TextDecoder().decode(zip.data(mt)).trim() === 'application/epub+zip') return prepareEpub(zip);
    throw new ConversionError('err.unknownPackage');
  }
  if (startsWith(bytes, CFB)) throw new ConversionError('err.legacyOffice');
  if (startsWith(bytes, [0x25, 0x50, 0x44, 0x46])) throw new ConversionError('err.pdf');
  if (isRtf(bytes)) return prepareRtf(bytes);
  if (looksBinary(bytes)) throw new ConversionError('err.binary');
  switch (e) {
    case 'html': case 'htm': case 'shtml': return prepareHtml(bytes, false);
    case 'xhtml': return prepareHtml(bytes, true);
    case 'fb2': return prepareXml(bytes, 'fb2', FB2_PROFILE, 'application/x-fictionbook+xml');
    case 'svg': return prepareXml(bytes, 'svg', SVG_PROFILE, 'image/svg+xml');
    case 'fodt': case 'fods': case 'fodp': case 'fodg': return prepareFlatOdf(bytes, e as FormatId);
    case 'xml': return sniffXml(bytes);
    case 'json': return prepareJson(bytes);
    case 'md': case 'markdown': return prepareMarkdown(bytes);
    case 'srt': return prepareSrt(bytes);
    case 'vtt': return prepareVtt(bytes);
    case 'ass': case 'ssa': return prepareAss(bytes);
    case 'csv': case 'tsv': return preparePlain(bytes, 'csv', e === 'tsv' ? 'text/tab-separated-values' : 'text/csv');
  }
  // unknown extension: look at the content
  const head = new TextDecoder('utf-8').decode(bytes.subarray(0, 512)).replace(/^\ufeff/, '').trimStart();
  if (/^<!doctype html|^<html[\s>]/i.test(head)) return prepareHtml(bytes, false);
  if (head.startsWith('<?xml') || /^<[A-Za-z]/.test(head)) return sniffXml(bytes);
  if (head.startsWith('WEBVTT')) return prepareVtt(bytes);
  return preparePlain(bytes, 'text', 'text/plain');
}

function sniffXml(bytes: Uint8Array): Prepared {
  const head = new TextDecoder('utf-8').decode(bytes.subarray(0, 4096));
  if (/<FictionBook[\s>]/.test(head)) return prepareXml(bytes, 'fb2', FB2_PROFILE, 'application/x-fictionbook+xml');
  if (/<svg[\s>]/.test(head)) return prepareXml(bytes, 'svg', SVG_PROFILE, 'image/svg+xml');
  if (/<office:document[\s>]/.test(head)) return prepareFlatOdf(bytes, 'fodt');
  if (/<html[\s>]/i.test(head)) return prepareHtml(bytes, true);
  return prepareXml(bytes, 'xml', GENERIC_XML_PROFILE, 'application/xml');
}


export { outputName };

export function convertDocument(engine: Converter, job: DocumentJob): DocumentResult {
  const prepared = prepareDocument(job.bytes, job.name, { engine, options: job.options, depth: 0 });
  const paras = prepared.paras;
  const from: Script = job.from === 'auto' ? engine.detect(sampleText(paras)) : job.from;
  const warnings = [...prepared.warnings];
  let bytes = job.bytes, stats = { segments: 0, changed: 0 };
  if (from === job.to) warnings.push('warn.sameScript');
  else {
    stats = convertParagraphs(engine, paras, from, job.to, job.options);
    bytes = prepared.finish(job.to) ?? job.bytes;
  }
  if (stats.segments === 0 && from !== job.to) warnings.push('warn.noText');
  return {
    name: outputName(job.name, job.to),
    bytes,
    mime: prepared.mime,
    format: prepared.format,
    from,
    encoding: prepared.encoding,
    stats: { ...stats, parts: prepared.parts },
    warnings
  };
}
