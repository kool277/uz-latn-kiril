import { beforeAll, describe, expect, it } from 'vitest';
import { convertDocument } from '../../src/app/engine/document';
import { decodeText } from '../../src/app/engine/encoding';
import { chunkAtWhitespace } from '../../src/app/engine/formats/text';
import type { Converter, Script, Source } from '../../src/app/engine/types';
import { wasmEngine } from './helpers';

let U: Converter;
beforeAll(async () => { U = await wasmEngine(); });

const utf8 = (s: string) => new TextEncoder().encode(s);
const text = (b: Uint8Array) => new TextDecoder().decode(b);
function run(name: string, input: string | Uint8Array, to: Script = 'lat', from: Source = 'auto') {
  return convertDocument(U, { name, bytes: typeof input === 'string' ? utf8(input) : input, from, to, options: {} });
}

/** Windows-1251 bytes for Cyrillic test strings (Uzbek-specific letters are not in the code page). */
function cp1251(s: string): Uint8Array {
  return Uint8Array.from([...s].map(ch => {
    const c = ch.charCodeAt(0);
    if (c < 0x80) return c;
    if (c >= 0x410 && c <= 0x44f) return c - 0x410 + 0xc0;
    if (c === 0x401) return 0xa8;
    if (c === 0x451) return 0xb8;
    if (c === 0x40e) return 0xa1;
    if (c === 0x45e) return 0xa2;
    throw new Error('not in cp1251: ' + ch);
  }));
}

describe('plain text and CSV', () => {
  it('UTF-8 stays UTF-8, line endings and BOM survive', () => {
    const r = run('a.txt', '\ufeffТошкент шаҳри\r\nЎзбекистон\r\n');
    expect(r.encoding).toBe('utf-8');
    expect(Array.from(r.bytes.subarray(0, 3))).toEqual([0xef, 0xbb, 0xbf]);
    expect(new TextDecoder('utf-8', { ignoreBOM: true }).decode(r.bytes)).toBe('\ufeffToshkent shahri\r\nOʻzbekiston\r\n');
  });

  it('Windows-1251 is recognised and written as UTF-8 with a BOM', () => {
    const r = run('eski.txt', cp1251('Тошкент шаҳри эмас, Ёзувчи ва ўқувчи'.replace(/[ҳқ]/g, 'х')), 'lat');
    expect(r.encoding).toBe('windows-1251');
    expect(decodeText(r.bytes).text).toBe('Toshkent shaxri emas, Yozuvchi va oʻxuvchi');
  });

  it('UTF-16 keeps its encoding', () => {
    const s = 'Шаҳар';
    const b = new Uint8Array(2 + s.length * 2);
    b.set([0xff, 0xfe]);
    for (let i = 0; i < s.length; i++) { b[2 + 2 * i] = s.charCodeAt(i) & 0xff; b[3 + 2 * i] = s.charCodeAt(i) >> 8; }
    const r = run('u16.txt', b);
    expect(r.encoding).toBe('utf-16le');
    expect(new TextDecoder('utf-16le').decode(r.bytes)).toBe('Shahar');
  });

  it('CSV: quotes, separators and numbers pass through', () => {
    expect(text(run('t.csv', 'Шаҳар;Аҳоли\n"Тошкент, пойтахт";3000000\n').bytes)).toBe('Shahar;Aholi\n"Toshkent, poytaxt";3000000\n');
  });

  it('large text: chunks end at whitespace and convert exactly like the whole text', () => {
    const big = Array.from({ length: 5000 }, (_, i) => `${i}. ШАҲАР маркази www.example.uz/${i} Исҳоқ кўчаси, мўъжиза\n`).join('');
    const chunks = chunkAtWhitespace(big, 4096);
    expect(chunks.length).toBeGreaterThan(50);
    for (const [, end] of chunks.slice(0, -1)) expect(/\s/.test(big[end - 1])).toBe(true);
    expect(text(run('big.txt', big).bytes)).toBe(U.convert(big, 'cyr', 'lat'));
  });
});

describe('subtitles', () => {
  it('SRT: numbers, timings and tags stay; a word split by a tag keeps its casing', () => {
    const srt = '1\n00:00:01,000 --> 00:00:04,000\n<b>ШАҲ</b>АР ҳақида\n{\\an8}Тошкент\n\n2\n00:00:05,000 --> 00:00:06,500\nЯхши\n';
    expect(text(run('a.srt', srt).bytes)).toBe('1\n00:00:01,000 --> 00:00:04,000\n<b>SHAH</b>AR haqida\n{\\an8}Toshkent\n\n2\n00:00:05,000 --> 00:00:06,500\nYaxshi\n');
  });

  it('VTT: header, cue settings, identifiers and NOTE blocks stay (Latin → Cyrillic)', () => {
    const vtt = 'WEBVTT Kind: captions\n\nNOTE izoh shu yerda\n\nintro\n00:01.000 --> 00:04.000 align:start line:0\n<v Ali>Salom, doʻstim</v>\n';
    expect(text(run('a.vtt', vtt, 'cyr').bytes)).toBe('WEBVTT Kind: captions\n\nNOTE izoh shu yerda\n\nintro\n00:01.000 --> 00:04.000 align:start line:0\n<v Ali>Салом, дўстим</v>\n');
  });

  it('ASS: only the Text field of Dialogue lines changes, override tags and \\N stay', () => {
    const ass = '[Script Info]\nTitle: Kino\n\n[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n' +
      'Dialogue: 0,0:00:01.00,0:00:02.00,Default,Ali,0,0,0,,{\\i1}Shahar{\\i0}\\Nmarkazi, choy\n';
    expect(text(run('a.ass', ass, 'new').bytes)).toBe(ass.replace('{\\i1}Shahar{\\i0}\\Nmarkazi, choy', '{\\i1}Şahar{\\i0}\\Nmarkazi, çoy'));
  });
});

describe('Markdown and JSON', () => {
  it('Markdown: code, link targets, front matter and reference labels stay', () => {
    const md = '---\ntitle: shahar\n---\n# Shahar\n\nBu `shahar` emas, [shahar](docs/shahar.md) va <b>Sh</b>ahar.\n\n```\nshahar = 1\n```\n\n    kod shahar\n\n[ref]: https://shahar.uz\n';
    expect(text(run('a.md', md, 'cyr').bytes)).toBe('---\ntitle: shahar\n---\n# Шаҳар\n\nБу `shahar` эмас, [шаҳар](docs/shahar.md) ва <b>Ш</b>аҳар.\n\n```\nshahar = 1\n```\n\n    kod shahar\n\n[ref]: https://shahar.uz\n');
  });

  it('JSON: string values convert, keys and escapes stay valid', () => {
    const json = '{"shahar": "Toshkent shahri", "list": ["choy", "\\"qo\'shtirnoq\\""], "n": 5, "escaped": "\\u0053hahar"}';
    const out = text(run('a.json', json, 'cyr').bytes);
    expect(JSON.parse(out)).toEqual({ shahar: 'Тошкент шаҳри', list: ['чой', '"қўштирноқ"'], n: 5, escaped: 'Шаҳар' });
    expect(out.startsWith('{"shahar": ')).toBe(true);
  });
});

describe('markup', () => {
  it('HTML: text, alt/title and meta description convert; scripts, code, URLs and translate=no stay', () => {
    const html = '<!doctype html><html lang="uz-Cyrl"><head><meta charset="utf-8"><title>Шаҳар</title>' +
      '<meta name="description" content="Тошкент ҳақида"><script>var шаҳар = 1;</script><style>.ш{}</style></head>' +
      '<body><p><b>ШАҲ</b>АР &amp; <a href="/шаҳар" title="Ҳавола">ҳавола</a> https://шаҳар.uz</p>' +
      '<img src="a.png" alt="Расм"><code>шаҳар()</code><span translate="no">Тошкент</span><p>Ўз&nbsp;бек &mdash; &unknown; эл</p></body></html>';
    const out = text(run('a.html', html).bytes);
    expect(out).toBe('<!doctype html><html lang="uz-Latn"><head><meta charset="utf-8"><title>Shahar</title>' +
      '<meta name="description" content="Toshkent haqida"><script>var шаҳар = 1;</script><style>.ш{}</style></head>' +
      '<body><p><b>SHAH</b>AR &amp; <a href="/шаҳар" title="Havola">havola</a> https://шаҳар.uz</p>' +
      '<img src="a.png" alt="Rasm"><code>шаҳар()</code><span translate="no">Тошкент</span><p>Oʻz&nbsp;bek — &unknown; el</p></body></html>');
  });

  it('HTML in Windows-1251: decoded by its meta charset, written as UTF-8 and the meta says so', () => {
    const html = '<html><head><meta http-equiv="Content-Type" content="text/html; charset=windows-1251"></head><body>Ёзувчи</body></html>';
    const out = text(run('old.html', cp1251(html)).bytes);
    expect(out).toBe('<html><head><meta http-equiv="Content-Type" content="text/html; charset=utf-8"></head><body>Yozuvchi</body></html>');
  });

  it('FB2 in Windows-1251: text converts, binaries and genres stay, declaration becomes UTF-8', () => {
    const fb2 = '<?xml version="1.0" encoding="windows-1251"?><FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0">' +
      '<description><title-info><genre>prose</genre><author><first-name>Абдулла</first-name><last-name>Қодирий</last-name></author>' +
      '<book-title>Ўтган кунлар</book-title></title-info></description><body><section><p>Ёз <emphasis>фас</emphasis>ли</p></section></body>' +
      '<binary id="i.jpg" content-type="image/jpeg">QUJD</binary></FictionBook>';
    const bytes = cp1251(fb2.replace('Қ', 'К'));
    const out = text(run('kitob.fb2', bytes).bytes);
    expect(out).toBe('<?xml version="1.0" encoding="UTF-8"?><FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0">' +
      '<description><title-info><genre>prose</genre><author><first-name>Abdulla</first-name><last-name>Kodiriy</last-name></author>' +
      '<book-title>Oʻtgan kunlar</book-title></title-info></description><body><section><p>Yoz <emphasis>fas</emphasis>li</p></section></body>' +
      '<binary id="i.jpg" content-type="image/jpeg">QUJD</binary></FictionBook>');
  });

  it('SVG: <text>, <title> and <desc> convert, attributes and styles do not', () => {
    const svg = '<svg xmlns="http://www.w3.org/2000/svg"><title>Харита</title><style>text{font:Шрифт}</style>' +
      '<text x="1" id="шаҳар">Тош<tspan font-weight="bold">кент</tspan></text></svg>';
    expect(text(run('a.svg', svg).bytes)).toBe('<svg xmlns="http://www.w3.org/2000/svg"><title>Xarita</title><style>text{font:Шрифт}</style>' +
      '<text x="1" id="шаҳар">Tosh<tspan font-weight="bold">kent</tspan></text></svg>');
  });

  it('generic XML: element text converts, CDATA too, comments and attributes stay', () => {
    const xml = '<?xml version="1.0"?><!-- шаҳар --><root a="шаҳар"><item>Шаҳар &amp; қишлоқ</item><c><![CDATA[Ёз <фасли>]]></c></root>';
    expect(text(run('a.xml', xml).bytes)).toBe('<?xml version="1.0"?><!-- шаҳар --><root a="шаҳар"><item>Shahar &amp; qishloq</item><c><![CDATA[Yoz <fasli>]]></c></root>');
  });
});

describe('RTF', () => {
  it('\\\'hh text in the font code page and \\u escapes convert; groups, fonts and fields stay', () => {
    const rtf = '{\\rtf1\\ansi\\ansicpg1252\\deff0{\\fonttbl{\\f0\\fcharset204 Arial;}}' +
      '{\\b \\\'d8\\\'c0}\\u1202?\\\'c0\\\'d0 \\u1179?\\\'e8\\u1096?\\\'eb\\\'ee\\\'ea\\par ' +
      '{\\field{\\*\\fldinst HYPERLINK "http://shahar.uz"}{\\fldrslt \\\'d2\\\'ee\\\'f8}}\\par}';
    const out = new TextDecoder('latin1').decode(run('a.rtf', utf8(rtf)).bytes);
    expect(out).toBe('{\\rtf1\\ansi\\ansicpg1252\\deff0{\\fonttbl{\\f0\\fcharset204 Arial;}}' +
      '{\\b SHA}HAR qishlok\\par ' +
      '{\\field{\\*\\fldinst HYPERLINK "http://shahar.uz"}{\\fldrslt Tosh}}\\par}');
  });

  it('\\rquote (how Word writes the mark in Oʻzbek) is part of the word', () => {
    const rtf = '{\\rtf1\\ansi O\\rquote zbek}';
    expect(new TextDecoder('latin1').decode(run('a.rtf', utf8(rtf), 'cyr').bytes)).toBe('{\\rtf1\\ansi \\u1038?\\u1079?\\u1073?\\u1077?\\u1082?}');
  });

  it('Latin → Cyrillic writes \\u escapes with the right fallback count', () => {
    const rtf = '{\\rtf1\\ansi\\uc0 {\\i Sh}ahar}';
    expect(new TextDecoder('latin1').decode(run('a.rtf', utf8(rtf), 'cyr').bytes)).toBe('{\\rtf1\\ansi\\uc0 {\\i \\u1064 }\\u1072 \\u1203 \\u1072 \\u1088 }');
  });
});

describe('errors', () => {
  it.each([
    ['legacy Word', 'a.doc', Uint8Array.from([0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1, 0, 0]), 'err.legacyOffice'],
    ['PDF', 'a.pdf', utf8('%PDF-1.7\n'), 'err.pdf'],
    ['binary', 'a.bin', Uint8Array.from([1, 0, 2, 0, 0, 3, 0, 0, 0, 9]), 'err.binary'],
    ['broken zip', 'a.docx', Uint8Array.from([0x50, 0x4b, 0x03, 0x04, 1, 2, 3]), 'err.corrupt']
  ])('%s', (_label, name, bytes, code) => {
    expect(() => run(name, bytes)).toThrow(code);
  });
});
