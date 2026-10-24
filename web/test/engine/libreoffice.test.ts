import { spawnSync } from 'node:child_process';
import { mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { convertDocument, prepareDocument } from '../../src/app/engine/document';
import type { Converter, Script } from '../../src/app/engine/types';
import { DOCS, wasmEngine } from './helpers';

// End to end: LibreOffice must open every converted file, and the text it sees must be exactly the
// conversion of the text it sees in the original. Runs only where `soffice` is installed (CI installs it).
const hasSoffice = spawnSync('soffice', ['--version'], { stdio: 'ignore' }).status === 0;

describe.skipIf(!hasSoffice)('converted files in LibreOffice', () => {
  let U: Converter;
  let dir: string;
  const writer = ['writer.docx', 'writer.odt', 'writer.rtf', 'writer.fodt', 'writer.html'];
  const calc = ['calc.xlsx', 'calc.ods', 'calc.fods'];
  const impress = ['impress.pptx', 'impress.odp', 'impress.fodp'];
  const targets: Script[] = ['lat', 'new'];

  const soffice = (filter: string, files: string[], outdir: string) => {
    const profile = pathToFileURL(join(dir, 'profile')).href;
    const r = spawnSync('soffice', [`-env:UserInstallation=${profile}`, '--headless', '--norestore', '--convert-to', filter, '--outdir', outdir, ...files],
      { cwd: dir, encoding: 'utf8', timeout: 300000 });
    expect(r.status, r.stderr).toBe(0);
  };
  // in.writer-docx.docx → export in.writer-docx.txt: every export gets its own name
  const stem = (p: string, f: string) => `${p}.${f.replace('.', '-')}`;
  const file = (p: string, f: string) => `${stem(p, f)}.${f.split('.').pop()}`;
  const read = (f: string) => readFileSync(join(dir, f), 'utf8').replace(/^﻿/, '').replace(/[ \t]+$/gm, '').trimEnd();

  beforeAll(async () => {
    U = await wasmEngine();
    dir = mkdtempSync(join(tmpdir(), 'uzt-lo-'));
    for (const f of [...writer, ...calc, ...impress]) {
      const bytes = new Uint8Array(readFileSync(join(DOCS, f)));
      writeFileSync(join(dir, file('in', f)), bytes);
      for (const to of targets) {
        const r = convertDocument(U, { name: f, bytes, from: 'auto', to, options: {} });
        writeFileSync(join(dir, file(to, f)), r.bytes);
      }
    }
    const names = (list: string[]) => list.flatMap(f => ['in', ...targets].map(p => file(p, f)));
    soffice('txt:Text (encoded):UTF8', names(writer), join(dir, 'txt'));
    soffice('csv:Text - txt - csv (StarCalc):44,34,76', names(calc), join(dir, 'csv'));
    soffice('odp', names(impress), join(dir, 'odp'));
  }, 600000);

  afterAll(() => rmSync(dir, { recursive: true, force: true }));


  for (const f of writer) {
    for (const to of targets) {
      it(`${f} → ${to}: Writer shows the converted text`, () => {
        expect(read(`txt/${stem(to, f)}.txt`)).toBe(U.convert(read(`txt/${stem('in', f)}.txt`), 'cyr', to));
      });
    }
  }
  for (const f of calc) {
    for (const to of targets) {
      it(`${f} → ${to}: Calc shows the converted cells`, () => {
        expect(read(`csv/${stem(to, f)}.csv`)).toBe(U.convert(read(`csv/${stem('in', f)}.csv`), 'cyr', to));
      });
    }
  }
  for (const f of impress) {
    for (const to of targets) {
      it(`${f} → ${to}: Impress opens it and shows the converted slides`, () => {
        const text = (p: string) => prepareDocument(new Uint8Array(readFileSync(join(dir, 'odp', `${stem(p, f)}.odp`))), 'x.odp', { engine: U, options: {}, depth: 0 })
          .paras.map(q => q.items.map(it => (typeof it === 'string' ? it : it.text)).join(''));
        const before = text('in'), after = text(to);
        expect(after.length).toBe(before.length);
        after.forEach((t, i) => expect(t).toBe(U.convert(before[i], 'cyr', to)));
      });
    }
  }

  it('produced every export', () => {
    expect(readdirSync(join(dir, 'txt')).length).toBe(writer.length * 3);
    expect(readdirSync(join(dir, 'csv')).length).toBe(calc.length * 3);
    expect(readdirSync(join(dir, 'odp')).length).toBe(impress.length * 3);
  });
});
