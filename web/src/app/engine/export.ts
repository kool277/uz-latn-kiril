import { escapeXmlText } from './text-model';
import { Script } from './types';
import { buildZip } from './zip';

/** Builds a file from plain text: the "export" of the text converter. Lines become paragraphs. */

export type ExportFormat = 'txt' | 'docx' | 'odt' | 'html';

export const EXPORT_MIME: Record<ExportFormat, string> = {
  txt: 'text/plain;charset=utf-8',
  docx: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  odt: 'application/vnd.oasis.opendocument.text',
  html: 'text/html;charset=utf-8'
};

const enc = new TextEncoder();
const LANG: Record<Script, { tag: string; script: string }> = {
  cyr: { tag: 'uz-Cyrl-UZ', script: 'Cyrl' },
  lat: { tag: 'uz-Latn-UZ', script: 'Latn' },
  new: { tag: 'uz-Latn-UZ', script: 'Latn' }
};

function splitLines(text: string): string[] {
  return text.replace(/\r\n?/g, '\n').split('\n');
}

function docx(text: string, script: Script): Uint8Array {
  const lang = LANG[script].tag;
  const paras = splitLines(text).map(line => {
    if (!line) return '<w:p/>';
    const runs = line.split('\t').map(part => (part ? `<w:t xml:space="preserve">${escapeXmlText(part)}</w:t>` : '')).join('<w:tab/>');
    return `<w:p><w:r>${runs}</w:r></w:p>`;
  }).join('');
  const W = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"';
  const now = new Date().toISOString().replace(/\.\d+Z$/, 'Z');
  return buildZip([
    { name: '[Content_Types].xml', data: enc.encode('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">' +
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>' +
      '<Default Extension="xml" ContentType="application/xml"/>' +
      '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>' +
      '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>' +
      '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>' +
      '</Types>') },
    { name: '_rels/.rels', data: enc.encode('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' +
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>' +
      '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>' +
      '</Relationships>') },
    { name: 'word/_rels/document.xml.rels', data: enc.encode('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' +
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>' +
      '</Relationships>') },
    { name: 'word/document.xml', data: enc.encode(`<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document ${W}><w:body>${paras}` +
      '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1134" w:right="850" w:bottom="1134" w:left="1701" w:header="708" w:footer="708" w:gutter="0"/></w:sectPr>' +
      '</w:body></w:document>') },
    { name: 'word/styles.xml', data: enc.encode(`<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:styles ${W}>` +
      '<w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:cs="Times New Roman" w:eastAsia="Times New Roman"/>' +
      `<w:sz w:val="28"/><w:szCs w:val="28"/><w:lang w:val="${lang}" w:eastAsia="${lang}" w:bidi="ar-SA"/></w:rPr></w:rPrDefault>` +
      '<w:pPrDefault><w:pPr><w:spacing w:after="120" w:line="276" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults>' +
      '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style>' +
      '</w:styles>') },
    { name: 'docProps/core.xml', data: enc.encode('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
      '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" ' +
      'xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">' +
      `<dc:creator>latin.jaybi.uz</dc:creator><dc:language>${lang}</dc:language>` +
      `<dcterms:created xsi:type="dcterms:W3CDTF">${now}</dcterms:created><dcterms:modified xsi:type="dcterms:W3CDTF">${now}</dcterms:modified>` +
      '</cp:coreProperties>') }
  ]);
}

function odtSpaces(s: string): string {
  // runs of spaces need <text:s/> in ODF; a leading space too
  return escapeXmlText(s).replace(/ {2,}/g, m => ' <text:s text:c="' + (m.length - 1) + '"/>').replace(/^ /, '<text:s/>');
}

function odt(text: string, script: Script): Uint8Array {
  const NS = 'xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" ' +
    'xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0" xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0" ' +
    'xmlns:meta="urn:oasis:names:tc:opendocument:xmlns:meta:1.0" xmlns:dc="http://purl.org/dc/elements/1.1/"';
  const paras = splitLines(text).map(line => '<text:p text:style-name="Standard">' + line.split('\t').map(odtSpaces).join('<text:tab/>') + '</text:p>').join('');
  const { script: sc, tag } = LANG[script];
  return buildZip([
    { name: 'mimetype', data: enc.encode('application/vnd.oasis.opendocument.text'), store: true },
    { name: 'META-INF/manifest.xml', data: enc.encode('<?xml version="1.0" encoding="UTF-8"?>' +
      '<manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0" manifest:version="1.3">' +
      '<manifest:file-entry manifest:full-path="/" manifest:version="1.3" manifest:media-type="application/vnd.oasis.opendocument.text"/>' +
      '<manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml"/>' +
      '<manifest:file-entry manifest:full-path="styles.xml" manifest:media-type="text/xml"/>' +
      '<manifest:file-entry manifest:full-path="meta.xml" manifest:media-type="text/xml"/>' +
      '</manifest:manifest>') },
    { name: 'styles.xml', data: enc.encode(`<?xml version="1.0" encoding="UTF-8"?><office:document-styles ${NS} office:version="1.3"><office:styles>` +
      '<style:default-style style:family="paragraph"><style:paragraph-properties fo:margin-bottom="0.21cm"/>' +
      `<style:text-properties style:font-name="Times New Roman" fo:font-size="14pt" fo:language="uz" fo:country="UZ" fo:script="${sc}" style:rfc-language-tag="${tag}"/></style:default-style>` +
      '<style:style style:name="Standard" style:family="paragraph" style:class="text"/>' +
      '</office:styles></office:document-styles>') },
    { name: 'content.xml', data: enc.encode(`<?xml version="1.0" encoding="UTF-8"?><office:document-content ${NS} office:version="1.3">` +
      `<office:body><office:text>${paras}</office:text></office:body></office:document-content>`) },
    { name: 'meta.xml', data: enc.encode(`<?xml version="1.0" encoding="UTF-8"?><office:document-meta ${NS} office:version="1.3"><office:meta>` +
      `<meta:generator>latin.jaybi.uz</meta:generator><dc:language>${tag}</dc:language></office:meta></office:document-meta>`) }
  ]);
}

function html(text: string, script: Script): Uint8Array {
  const lang = script === 'cyr' ? 'uz-Cyrl' : 'uz-Latn';
  const esc = (s: string) => s.replace(/[&<>]/g, c => (c === '&' ? '&amp;' : c === '<' ? '&lt;' : '&gt;'));
  const body = splitLines(text).map(l => (l ? `<p>${esc(l)}</p>` : '')).join('\n');
  return enc.encode(`<!doctype html>\n<html lang="${lang}">\n<head>\n<meta charset="utf-8">\n<meta name="viewport" content="width=device-width, initial-scale=1">\n` +
    `<meta name="generator" content="latin.jaybi.uz">\n<title></title>\n<style>body{font:1.05rem/1.6 system-ui,sans-serif;max-width:46rem;margin:2rem auto;padding:0 1rem}p{margin:0 0 .6em;white-space:pre-wrap}</style>\n</head>\n<body>\n${body}\n</body>\n</html>\n`);
}

export function exportText(text: string, format: ExportFormat, script: Script): Uint8Array {
  switch (format) {
    case 'docx': return docx(text, script);
    case 'odt': return odt(text, script);
    case 'html': return html(text, script);
    default: return enc.encode(text);
  }
}
