import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { beforeAll, describe, expect, it } from 'vitest';
import { convertDocument, prepareDocument } from '../../src/app/engine/document';
import type { Paragraph } from '../../src/app/engine/text-model';
import type { Converter, Script } from '../../src/app/engine/types';
import { parseAttrs, scanXml } from '../../src/app/engine/xml';
import { ZipArchive } from '../../src/app/engine/zip';
import { DOCS, wasmEngine } from './helpers';

const files = readdirSync(DOCS).filter(f => !f.startsWith('.')).sort();
let U: Converter;
beforeAll(async () => { U = await wasmEngine(); });

const paraText = (p: Paragraph) => p.items.map(it => (typeof it === 'string' ? it : it.text)).join('');
const texts = (bytes: Uint8Array, name: string) =>
  prepareDocument(bytes, name, { engine: U, options: {}, depth: 0 }).paras.map(paraText);

// attributes whose values may legitimately change: converted alt text / names, language tags, xml:space
const MAY_CHANGE = /(^|:)(descr|title|name|alt|placeholder|aria-label|content|lang|altLang|val|eastAsia|bidi|rfc-language-tag|script|space)$/;

/** Every tag and attribute must be identical in input and output; only text and a few attributes change. */
function sameMarkup(a: string, b: string): string | null {
  const tags = (s: string) => {
    const out: Array<{ name: string; attrs: Array<[string, string]> }> = [];
    scanXml(s, {
      start(name, start, nameEnd, end, self) {
        out.push({ name, attrs: parseAttrs(s, nameEnd, self ? end - 2 : end - 1).map(x => [x.name, s.slice(x.start, x.end)]) });
      },
      end(name) { out.push({ name: '/' + name, attrs: [] }); },
      text() {},
      cdata() {}
    });
    return out;
  };
  const ta = tags(a), tb = tags(b);
  if (ta.length !== tb.length) return `tag count ${ta.length} vs ${tb.length}`;
  for (let i = 0; i < ta.length; i++) {
    if (ta[i].name !== tb[i].name) return `tag ${i}: ${ta[i].name} vs ${tb[i].name}`;
    const extra = tb[i].attrs.filter(([n]) => n === 'xml:space' && !ta[i].attrs.some(([m]) => m === n));
    const attrsB = tb[i].attrs.filter(x => !extra.includes(x));
    if (ta[i].attrs.length !== attrsB.length) return `attributes of ${ta[i].name}`;
    for (let k = 0; k < attrsB.length; k++) {
      const [na, va] = ta[i].attrs[k], [nb, vb] = attrsB[k];
      if (na !== nb || (va !== vb && !MAY_CHANGE.test(na))) return `${ta[i].name} @${na}: ${va} → ${vb}`;
    }
  }
  return null;
}

describe.each(files)('%s', file => {
  const input = new Uint8Array(readFileSync(join(DOCS, file)));

  for (const to of ['lat', 'new'] as Script[]) {
    it(`cyr → ${to}: every paragraph converted, markup untouched`, () => {
      const r = convertDocument(U, { name: file, bytes: input, from: 'auto', to, options: {} });
      expect(r.from).toBe('cyr');
      expect(r.name).toBe(file.replace(/(\.[^.]+)$/, `-${to}$1`));
      expect(r.stats.changed).toBeGreaterThan(0);

      const before = texts(input, file), after = texts(r.bytes, file);
      expect(after.length).toBe(before.length);
      after.forEach((t, i) => expect(t).toBe(U.convert(before[i], 'cyr', to)));

      if (ZipArchive.isZip(input)) {
        const zin = ZipArchive.read(input), zout = ZipArchive.read(r.bytes);
        expect(zout.entries.map(e => e.name)).toEqual(zin.entries.map(e => e.name));
        for (const e of zin.entries) {
          const a = zin.data(e), b = zout.data(zout.get(e.name)!);
          if (Buffer.from(a).equals(Buffer.from(b))) continue;
          expect(e.name, 'only XML parts change').toMatch(/\.(xml|x?html?|opf|ncx)$/);
          expect(sameMarkup(new TextDecoder().decode(a), new TextDecoder().decode(b)), e.name).toBeNull();
        }
      } else if (/\.(fodt|fods|fodp|html)$/.test(file)) {
        expect(sameMarkup(new TextDecoder().decode(input), new TextDecoder().decode(r.bytes))).toBeNull();
      }

      // and back to Cyrillic: the same invariant in the other direction
      const back = convertDocument(U, { name: r.name, bytes: r.bytes, from: to, to: 'cyr', options: {} });
      const cyr = texts(back.bytes, file);
      cyr.forEach((t, i) => expect(t).toBe(U.convert(after[i], to, 'cyr')));
    });
  }
});

describe('details that matter', () => {
  const docx = new Uint8Array(readFileSync(join(DOCS, 'writer.docx')));
  const part = (bytes: Uint8Array, name: string) => ZipArchive.read(bytes).text(ZipArchive.read(bytes).get(name)!);

  it('a word split across bold/plain runs keeps its casing and each run keeps its formatting', () => {
    const r = convertDocument(U, { name: 'a.docx', bytes: docx, from: 'auto', to: 'lat', options: {} });
    const xml = part(r.bytes, 'word/document.xml');
    expect(xml).toContain('<w:rPr><w:b/></w:rPr><w:t>SHAH</w:t>');
    expect(xml).toContain('<w:t xml:space="preserve">AR MARKAZI va </w:t>');
    expect(xml).toContain('<w:rPr><w:i/></w:rPr><w:t>Tosh</w:t>');
    expect(xml).toContain('<w:t>kent shahri.</w:t>');
    expect(xml).toContain('<w:t>https://latin.jaybi.uz</w:t>');
    expect(xml).toContain('<w:t>Obyekt, kompyuter va sirk; Isʼhoq moʻjiza koʻrdi.</w:t>');
  });

  it('footnotes, header, footer and comments are converted; comment authors are not', () => {
    const r = convertDocument(U, { name: 'a.docx', bytes: docx, from: 'auto', to: 'new', options: {} });
    expect(part(r.bytes, 'word/footnotes.xml')).toContain('Izoh: ğalaba va çiroq.');
    expect(part(r.bytes, 'word/header1.xml')).toContain('Sarlavha: Toşkent');
    expect(part(r.bytes, 'word/footer1.xml')).toContain('Sahifa oxiri');
    const comments = part(r.bytes, 'word/comments.xml');
    expect(comments).toContain('Şarh: yaxşi.');
    expect(comments).toContain('w:author="Муаллиф"');
  });

  it('spell-check language follows the script', () => {
    const lat = convertDocument(U, { name: 'a.docx', bytes: docx, from: 'auto', to: 'lat', options: {} });
    expect(part(lat.bytes, 'word/styles.xml')).toContain('w:val="uz-Latn-UZ"');
    expect(part(lat.bytes, 'word/styles.xml')).not.toContain('uz-Cyrl');
    const back = convertDocument(U, { name: 'a.docx', bytes: lat.bytes, from: 'lat', to: 'cyr', options: {} });
    expect(part(back.bytes, 'word/styles.xml')).toContain('w:val="uz-Cyrl-UZ"');
  });

  it('spreadsheet: numbers, formulas and sheet names stay; strings and rich text convert', () => {
    const xlsx = new Uint8Array(readFileSync(join(DOCS, 'calc.xlsx')));
    const r = convertDocument(U, { name: 'a.xlsx', bytes: xlsx, from: 'auto', to: 'lat', options: {} });
    const zin = ZipArchive.read(xlsx), zout = ZipArchive.read(r.bytes);
    const strings = zout.text(zout.get('xl/sharedStrings.xml')!);
    expect(strings).toContain('TOSH');
    expect(strings).toContain('KENT');
    expect(strings).toContain('Poytaxt, markaz');
    const sheet = 'xl/worksheets/sheet1.xml';
    expect(zout.text(zout.get(sheet)!)).toBe(zin.text(zin.get(sheet)!));
  });

  it('the same script in and out leaves the file byte-identical', () => {
    const r = convertDocument(U, { name: 'a.docx', bytes: docx, from: 'auto', to: 'cyr', options: {} });
    expect(r.warnings).toContain('warn.sameScript');
    expect(r.bytes).toBe(docx);
  });
});
