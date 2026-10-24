import { SEP_OBJECT } from '../text-model';
import { ConversionError, FormatId } from '../types';
import { ALLTEXT, ElementRule, IN_SCOPE, PARA, PRESERVE, SCOPE, SEP, SKIP, TEXT, XmlProfile, XmlRules } from '../xml';
import { ZipArchive } from '../zip';
import { PackageJob } from './xml-package';
import { PrepareContext, Prepared } from './prepared';

/**
 * Office Open XML (Word, Excel, PowerPoint 2007+ and their macro/template variants).
 * Only text runs change: <w:t>, <a:t>, <t> and a few attributes (alt text, table column names);
 * run properties, styles, fields, formulas, media and relationships are copied unchanged.
 */

const ns = (transitional: string, strict: string) => [transitional, strict];
const W = ns('http://schemas.openxmlformats.org/wordprocessingml/2006/main', 'http://purl.oclc.org/ooxml/wordprocessingml/main');
const A = ns('http://schemas.openxmlformats.org/drawingml/2006/main', 'http://purl.oclc.org/ooxml/drawingml/main');
const S = ns('http://schemas.openxmlformats.org/spreadsheetml/2006/main', 'http://purl.oclc.org/ooxml/spreadsheetml/main');
const P = ns('http://schemas.openxmlformats.org/presentationml/2006/main', 'http://purl.oclc.org/ooxml/presentationml/main');
const C = ns('http://schemas.openxmlformats.org/drawingml/2006/chart', 'http://purl.oclc.org/ooxml/drawingml/chart');
const WP = ns('http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing', 'http://purl.oclc.org/ooxml/drawingml/wordprocessingDrawing');
const PIC = ns('http://schemas.openxmlformats.org/drawingml/2006/picture', 'http://purl.oclc.org/ooxml/drawingml/picture');
const XDR = ns('http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing', 'http://purl.oclc.org/ooxml/drawingml/spreadsheetDrawing');
const TC = ['http://schemas.microsoft.com/office/spreadsheetml/2018/threadedcomments'];
const DC = ['http://purl.org/dc/elements/1.1/'];
const CP = ['http://schemas.openxmlformats.org/package/2006/metadata/core-properties'];

const obj: ElementRule = { kind: SEP, sep: SEP_OBJECT };
const altText: ElementRule = { kind: 0, attrs: ['descr', 'title'] };
const standalone: ElementRule = { kind: PARA | ALLTEXT };

function rulesFor(uris: string[], local: Record<string, ElementRule>, into: XmlRules): void {
  for (const u of uris) into[u] = { ...(into[u] ?? {}), ...local };
}

export const OOXML_PROFILE: XmlProfile = (() => {
  const r: XmlRules = {};
  rulesFor(W, {
    p: { kind: PARA },
    t: { kind: TEXT | PRESERVE },
    delText: { kind: TEXT | PRESERVE },
    del: { kind: PARA }, // deleted runs: their own context, so live text around them joins up
    moveFrom: { kind: PARA },
    instrText: { kind: SKIP }, // field codes (HYPERLINK "…", MERGEFIELD …)
    delInstrText: { kind: SKIP },
    tab: { kind: SEP, sep: '\t' },
    ptab: { kind: SEP, sep: '\t' },
    br: { kind: SEP, sep: '\n' },
    cr: { kind: SEP, sep: '\n' },
    noBreakHyphen: { kind: SEP, sep: '‑' },
    sym: obj, drawing: obj, object: obj, pict: obj,
    footnoteReference: obj, endnoteReference: obj, footnoteRef: obj, endnoteRef: obj,
    separator: obj, continuationSeparator: obj, pgNum: obj, annotationRef: obj,
    lang: { kind: 0, lang: W.map(u => `{${u}}val`).concat(W.map(u => `{${u}}eastAsia`), W.map(u => `{${u}}bidi`)) }
  }, r);
  const langRun: ElementRule = { kind: 0, lang: ['lang', 'altLang'] };
  rulesFor(A, { p: { kind: PARA }, t: { kind: TEXT }, br: { kind: SEP, sep: '\n' }, rPr: langRun, endParaRPr: langRun, defRPr: langRun }, r);
  rulesFor(S, {
    si: { kind: PARA }, is: { kind: PARA }, text: { kind: PARA },
    t: { kind: TEXT | PRESERVE },
    rPh: { kind: SKIP }, // phonetic guide runs
    tableColumn: { kind: 0, attrs: ['name'] } // must keep matching the converted header cells
  }, r);
  rulesFor(P, { text: standalone, cNvPr: altText }, r);
  rulesFor(C, { strCache: { kind: SCOPE }, pt: { kind: PARA }, v: { kind: TEXT | IN_SCOPE } }, r);
  rulesFor(WP, { docPr: altText }, r);
  rulesFor(PIC, { cNvPr: altText }, r);
  rulesFor(XDR, { cNvPr: altText }, r);
  rulesFor(TC, { text: standalone }, r);
  rulesFor(DC, { title: standalone, subject: standalone, description: standalone }, r);
  rulesFor(CP, { keywords: standalone, category: standalone }, r);
  return { rules: r };
})();

const EXCLUDED = /(^|\/)_rels\/|^customXml\/|\/theme\/|^xl\/(externalLinks|pivotCache|pivotTables|queryTables|connections)|(fontTable|settings|webSettings|calcChain|presProps|viewProps|tableStyles|commentAuthors|people)\.xml$/;
const MIME: Record<string, string> = {
  docx: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  xlsx: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  pptx: 'application/vnd.openxmlformats-officedocument.presentationml.presentation'
};

export function ooxmlKind(zip: ZipArchive): 'docx' | 'xlsx' | 'pptx' | null {
  if (!zip.get('[Content_Types].xml')) return null;
  if (zip.entries.some(e => e.name.startsWith('word/'))) return 'docx';
  if (zip.entries.some(e => e.name.startsWith('xl/'))) return 'xlsx';
  if (zip.entries.some(e => e.name.startsWith('ppt/'))) return 'pptx';
  return null;
}

/** The format's own MIME type, keeping macro-enabled and template variants. */
function mimeFor(kind: FormatId, name: string): string {
  const ext = name.toLowerCase().split('.').pop() ?? '';
  const variants: Record<string, string> = {
    docm: 'application/vnd.ms-word.document.macroEnabled.12',
    dotx: 'application/vnd.openxmlformats-officedocument.wordprocessingml.template',
    dotm: 'application/vnd.ms-word.template.macroEnabled.12',
    xlsm: 'application/vnd.ms-excel.sheet.macroEnabled.12',
    xltx: 'application/vnd.openxmlformats-officedocument.spreadsheetml.template',
    xltm: 'application/vnd.ms-excel.template.macroEnabled.12',
    pptm: 'application/vnd.ms-powerpoint.presentation.macroEnabled.12',
    potx: 'application/vnd.openxmlformats-officedocument.presentationml.template',
    potm: 'application/vnd.ms-powerpoint.template.macroEnabled.12',
    ppsx: 'application/vnd.openxmlformats-officedocument.presentationml.slideshow',
    ppsm: 'application/vnd.ms-powerpoint.slideshow.macroEnabled.12'
  };
  return variants[ext] ?? MIME[kind] ?? 'application/octet-stream';
}

const MAX_DEPTH = 2;

export function prepareOoxml(zip: ZipArchive, name: string, ctx: PrepareContext, prepareNested: (bytes: Uint8Array, name: string, ctx: PrepareContext) => Prepared | null): Prepared {
  const kind = ooxmlKind(zip);
  if (!kind) throw new ConversionError('err.unknownPackage');
  const job = new PackageJob(zip);
  const warnings: string[] = [];
  const root = kind === 'docx' ? 'word/' : kind === 'xlsx' ? 'xl/' : 'ppt/';
  for (const e of zip.entries) {
    const n = e.name;
    if (n.endsWith('/')) continue;
    if (n.startsWith(root + 'embeddings/') && /\.(docx|docm|xlsx|xlsm|pptx|pptm)$/i.test(n)) {
      if (ctx.depth < MAX_DEPTH) {
        try {
          const nested = prepareNested(zip.data(e), n, { ...ctx, depth: ctx.depth + 1 });
          if (nested) job.addNested(e, nested);
        } catch {
          warnings.push('warn.embeddedSkipped');
        }
      }
      continue;
    }
    if (!/\.xml$/i.test(n) || EXCLUDED.test(n)) continue;
    if (!(n.startsWith(root) || n === 'docProps/core.xml')) continue;
    if (/^xl\/worksheets\/sheet/.test(n)) {
      // sheets hold numbers and shared-string indices; only inline strings carry text
      const bytes = zip.data(e);
      if (!new TextDecoder().decode(bytes).includes('inlineStr')) continue;
    }
    job.addPart(e, OOXML_PROFILE);
  }
  return {
    format: kind,
    mime: mimeFor(kind, name),
    get paras() { return job.paras; },
    parts: job.count,
    warnings,
    finish: to => job.finish(to)
  };
}
