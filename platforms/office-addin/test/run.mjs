#!/usr/bin/env node
// Tests of the Office add-in: word-by-word conversion against the differential corpus, and the Word, Excel,
// PowerPoint and plain-text paths against the fakes in fakes.mjs.   node platforms/office-addin/test/run.mjs
import { existsSync, readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { fakeExcel, fakeOffice, fakePowerPoint, fakeWord } from './fakes.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '..', '..', '..');
const require = createRequire(import.meta.url);
const Uz = require(join(root, 'core', 'js', 'uztranslit.js'));
const A = require(join(here, '..', 'src', 'addin.js'))(Uz);

let ok = 0, bad = 0;
const eq = (name, got, want) => {
  const g = JSON.stringify(got), w = JSON.stringify(want);
  if (g === w) ok++;
  else { bad++; console.log(`FAIL ${name}\n  want ${w}\n  got  ${g}`); }
};

// ---------------------------------------------------------------- word by word == whole text
const diff = join(root, 'build', 'differential.json');
if (existsSync(diff)) {
  let n = 0, wrong = 0;
  for (const c of JSON.parse(readFileSync(diff, 'utf8')).cases) {
    if (c.from === 'auto') continue;
    n++;
    const got = A.apply(c.in, A.changes(c.in, c.from, c.to, c.options));
    if (got !== c.out) { wrong++; if (wrong <= 3) console.log('FAIL word by word', JSON.stringify(c.in), JSON.stringify(got), JSON.stringify(c.out)); }
  }
  eq(`word-by-word conversion equals the whole-text conversion (${n} differential cases)`, wrong, 0);
} else console.log('(differential corpus missing: node tools/make_differential.mjs)');

eq('words', A.words(' Bosh  sahifa\u00a0x\t'), [{ start: 1, end: 5 }, { start: 7, end: 13 }, { start: 14, end: 15 }]);
eq('resolve auto', A.resolve('auto', 'Шаҳар'), 'cyr');
eq('resolve fixed', A.resolve('lat', 'Шаҳар'), 'lat');
for (const [v, want] of [['5', "'5"], ['1e5', "'1e5"], ['=A1', "'=A1"], ['-x', "'-x"], ['TRUE', "'TRUE"], ['12.03.2024', "'12.03.2024"],
  ['Mar 5', "'Mar 5"], ['5 Mar', "'5 Mar"], ['50%', "'50%"], ['10:30', "'10:30"], ['Toshkent', 'Toshkent'], ['Mart oyi 5', 'Mart oyi 5'], ['', '']]) {
  eq(`excelText(${v})`, A.excelText(v), want);
}

const sets = { WordApi: '1.4', ExcelApi: '1.4', PowerPointApi: '1.5' };
const conv = (s, f, t) => Uz.convert(s, f, t);

// ---------------------------------------------------------------- Word
{
  const f = fakeWord({
    body: [[['Ш', 'b'], ['аҳар ', 'n'], ['маркази', 'i']], [['Сайт: https://latin.jaybi.uz/шаҳар', 'n']], [['Ер юзи', 'n']]],
    headers: [[['Сарлавҳа', 'h']]],
    tracking: 'TrackAll',
  });
  const office = fakeOffice('Word', sets);
  const r = await A.run({ Office: office, Word: f.Word }, { from: 'auto', to: 'lat', selection: true });
  eq('word: result', r, { from: 'cyr', words: 6 });
  eq('word: body text', f.text(f.body), ['Shahar markazi', 'Sayt: https://latin.jaybi.uz/шаҳар', 'Yer yuzi']);
  eq('word: each word keeps its formatting (a half-bold word takes its first letter\'s)', f.fmt(f.body)[0], 'bbbbbbbiiiiiii');
  eq('word: header', f.text(f.header), ['Sarlavha']);
  eq('word: change tracking paused, then back on', f.doc.modes, ['Off', 'TrackAll']);
}
{
  // selection inside the first paragraph: only the selected words change
  const f = fakeWord({ body: [[['Бир икки уч', 'n']], [['тўрт', 'n']]], selection: [0, 4, 0, 11] });
  const r = await A.word(f.Word, fakeOffice('Word', sets), { from: 'cyr', to: 'new', selection: true });
  eq('word selection: result', r, { from: 'cyr', words: 2 });
  eq('word selection: text', f.text(f.body), ['Бир ikki uç', 'тўрт']);
}
{
  const f = fakeWord({ body: [[['Shahar', 'n']]] });
  const r = await A.word(f.Word, fakeOffice('Word', sets), { from: 'auto', to: 'lat', selection: false });
  eq('word: nothing to do when the text is already in the target script', [r, f.text(f.body)], [{ from: 'lat', words: 0 }, ['Shahar']]);
}

// ---------------------------------------------------------------- Excel
{
  const f = fakeExcel([
    { '0,0': { value: 'Тошкент' }, '0,1': { value: 7, formula: '=LEN(A1)' }, '1,0': { value: 42 }, '1,1': { value: '5ь' },
      '2,0': { value: 'Шаҳар', formula: '=UPPER("Шаҳар")' }, '2,1': { value: 'Самарқанд' } },
    { '0,0': { value: 'Бухоро' } },
  ], [0, 0, 0, 0, 0]);
  const r = await A.run({ Office: fakeOffice('Excel', sets), Excel: f.Excel }, { from: 'auto', to: 'lat', selection: false });
  eq('excel: result', r, { from: 'cyr', cells: 4 });
  const c = (s, k) => f.sheets[s].cells[k];
  eq('excel: text converted', [c(0, '0,0').value, c(0, '2,1').value, c(1, '0,0').value], ['Toshkent', 'Samarqand', 'Buxoro']);
  eq('excel: a value that looks like a number stays text', [c(0, '1,1').value, c(0, '1,1').prefix], ['5', true]);
  eq('excel: formulas and numbers untouched', [c(0, '0,1').formula, c(0, '2,0').formula, c(0, '1,0').value], ['=LEN(A1)', '=UPPER("Шаҳар")', 42]);
}
{
  // a whole selected column: only its used part is read
  const f = fakeExcel([{ '0,0': { value: 'Ой' }, '1,0': { value: 'Кун' }, '0,1': { value: 'Йил' } }], [0, 0, 0, 1048575, 0]);
  const r = await A.excel(f.Excel, fakeOffice('Excel', sets), { from: 'cyr', to: 'new', selection: true });
  eq('excel selection: result', r, { from: 'cyr', cells: 2 });
  eq('excel selection: outside untouched', f.sheets[0].cells['0,1'].value, 'Йил');
}

// ---------------------------------------------------------------- PowerPoint
{
  const f = fakePowerPoint([
    [{ type: 'GeometricShape', runs: [['Ўзбекистон ', 'n'], ['ШАҲ', 'b'], ['АРЛАРИ', 'n']] }, { type: 'Image' },
     { type: 'Placeholder', noText: true }],
    [{ type: 'TextBox', runs: [['Ер', 'i'], [' юзи', 'n']] }],
  ]);
  const r = await A.run({ Office: fakeOffice('PowerPoint', sets), PowerPoint: f.PowerPoint }, { from: 'auto', to: 'new', selection: false });
  eq('powerpoint: result', r, { from: 'cyr', words: 4 });
  eq('powerpoint: text', f.text(), [['Özbekiston ŞAHARLARI', '', ''], ['Yer yuzi']]);
  eq('powerpoint: formatting per word', f.fmt()[0][0], 'nnnnnnnnnnnbbbbbbbbb');
}

// ---------------------------------------------------------------- hosts without the newer APIs: the selected text
{
  const office = fakeOffice('PowerPoint', { PowerPointApi: '1.2' }, 'Ишоқ ва шаҳар');
  const r = await A.run({ Office: office }, { from: 'auto', to: 'new', selection: true });
  eq('plain text fallback', [r, office.context.document.text], [{ from: 'cyr', words: 3, plain: true }, conv('Ишоқ ва шаҳар', 'cyr', 'new')]);
}

console.log(`${ok} passed, ${bad} failed (Office add-in)`);
process.exit(bad ? 1 : 0);
