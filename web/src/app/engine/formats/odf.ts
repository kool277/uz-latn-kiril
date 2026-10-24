import { SEP_OBJECT } from '../text-model';
import { ConversionError, FormatId } from '../types';
import { ALLTEXT, ElementRule, LANGTEXT, PARA, SEP, SKIP, XmlProfile, XmlRules } from '../xml';
import { ZipArchive } from '../zip';
import { PackageJob, XmlPart } from './xml-package';
import { Prepared } from './prepared';

/**
 * OpenDocument (LibreOffice / OpenOffice: odt, ods, odp, odg and the flat .fod* variants).
 * Every text node inside <text:p>/<text:h> belongs to the paragraph, whatever spans wrap it, so a word
 * split across differently formatted spans still converts as one word.
 */

const TEXT = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';
const OFFICE = 'urn:oasis:names:tc:opendocument:xmlns:office:1.0';
const DRAW = 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0';
const STYLE = 'urn:oasis:names:tc:opendocument:xmlns:style:1.0';
const FO = 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0';
const SVG = 'urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0';
const DC = 'http://purl.org/dc/elements/1.1/';
const META = 'urn:oasis:names:tc:opendocument:xmlns:meta:1.0';

const paragraph: ElementRule = { kind: PARA | ALLTEXT };
const obj: ElementRule = { kind: SEP, sep: SEP_OBJECT };
const skip: ElementRule = { kind: SKIP };

export const ODF_PROFILE: XmlProfile = {
  rules: ((): XmlRules => ({
    [TEXT]: {
      p: paragraph, h: paragraph, 'index-title-template': paragraph,
      s: { kind: SEP, sep: ' ' }, tab: { kind: SEP, sep: '\t' }, 'line-break': { kind: SEP, sep: '\n' },
      'sequence-decls': skip, 'variable-decls': skip, 'user-field-decls': skip
    },
    [OFFICE]: { script: skip, scripts: skip, forms: skip, 'binary-data': skip, 'event-listeners': skip, settings: skip },
    [DRAW]: { frame: obj, 'custom-shape': obj, rect: obj, ellipse: obj, image: obj, object: obj, g: obj },
    [SVG]: { title: paragraph, desc: paragraph },
    [DC]: { title: paragraph, description: paragraph, subject: paragraph, creator: skip, date: skip, language: { kind: LANGTEXT } },
    [META]: { keyword: paragraph, 'initial-creator': skip, 'creator-initials': skip, generator: skip, 'user-defined': skip, 'printed-by': skip },
    [STYLE]: {
      'text-properties': { kind: 0, lang: [`{${STYLE}}rfc-language-tag`], script: [`{${FO}}language`, `{${FO}}script`] }
    }
  }))()
};

const MIME: Record<string, FormatId> = {
  'application/vnd.oasis.opendocument.text': 'odt',
  'application/vnd.oasis.opendocument.text-template': 'odt',
  'application/vnd.oasis.opendocument.text-master': 'odt',
  'application/vnd.oasis.opendocument.spreadsheet': 'ods',
  'application/vnd.oasis.opendocument.spreadsheet-template': 'ods',
  'application/vnd.oasis.opendocument.presentation': 'odp',
  'application/vnd.oasis.opendocument.presentation-template': 'odp',
  'application/vnd.oasis.opendocument.graphics': 'odg',
  'application/vnd.oasis.opendocument.graphics-template': 'odg'
};

export function odfMime(zip: ZipArchive): string | null {
  const m = zip.get('mimetype');
  if (!m) return null;
  const mime = new TextDecoder().decode(zip.data(m)).trim();
  return mime in MIME ? mime : null;
}

export function prepareOdf(zip: ZipArchive): Prepared {
  const mime = odfMime(zip);
  if (!mime) throw new ConversionError('err.unknownPackage');
  const manifest = zip.get('META-INF/manifest.xml');
  if (manifest && zip.text(manifest).includes('encryption-data')) throw new ConversionError('err.encrypted');
  const job = new PackageJob(zip);
  for (const e of zip.entries) {
    // the main document and every embedded object (charts, formulas: "Object 1/content.xml")
    if (/(^|\/)(content|styles|meta)\.xml$/.test(e.name) && !e.name.startsWith('META-INF/')) job.addPart(e, ODF_PROFILE);
  }
  return {
    format: MIME[mime],
    mime,
    get paras() { return job.paras; },
    parts: job.count,
    warnings: [],
    finish: to => job.finish(to)
  };
}

/** Flat OpenDocument (.fodt/.fods/.fodp/.fodg): one XML file with the same vocabulary. */
export function prepareFlatOdf(bytes: Uint8Array, format: FormatId): Prepared {
  const part = XmlPart.fromBytes(bytes, ODF_PROFILE);
  return {
    format,
    mime: 'application/xml',
    paras: part.paras,
    parts: 1,
    encoding: part.source.encoding,
    warnings: [],
    finish: to => part.finish(to)
  };
}
