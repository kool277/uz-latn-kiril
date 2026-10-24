import { expect, Page, test } from '@playwright/test';
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { ZipArchive } from '../../src/app/engine/zip';
import { DOCS, wasmEngine } from '../engine/helpers';

/** Console errors, uncaught exceptions and CSP / Trusted Types violations. */
function watch(page: Page): string[] {
  const problems: string[] = [];
  page.on('console', m => { if (m.type() === 'error' || /Content.Security.Policy|Trusted.Type/i.test(m.text())) problems.push(m.text()); });
  page.on('pageerror', e => problems.push(e.message));
  return problems;
}

const target = (page: Page, name: string) => page.getByRole('radiogroup', { name: 'Qaysi alifboga' }).getByRole('radio', { name });

test('types Latin 1995 and gets Latin 2026', async ({ page }) => {
  const problems = watch(page);
  await page.goto('/');
  await page.getByTestId('source').fill("O'zbekiston shahri");
  await expect(page.getByTestId('result')).toHaveValue('Özbekiston şahri');
  await expect(page.getByTestId('detected')).toContainText('lotin 1995');
  await expect(page.getByTestId('engine')).toContainText('WebAssembly');
  expect(problems).toEqual([]);
});

test('deep link ?text=…&to=cyr', async ({ page }) => {
  await page.goto('/?text=' + encodeURIComponent('Toshkent shahri, Isʼhoq') + '&to=cyr');
  await expect(page.getByTestId('source')).toHaveValue('Toshkent shahri, Isʼhoq');
  await expect(page.getByTestId('result')).toHaveValue('Тошкент шаҳри, Исҳоқ');
  await expect(target(page, 'Кирилл')).toHaveAttribute('aria-checked', 'true');
});

test('auto-detection picks the other alphabet when the text is already in the target script', async ({ page }) => {
  await page.goto('/');
  await target(page, 'Yangi lotin').click();
  await page.getByTestId('source').fill('Özbekiston');
  await expect(page.getByTestId('result')).toHaveValue('Ўзбекистон');
});

test('a Word document keeps its runs, footnotes and comment authors', async ({ page }) => {
  const problems = watch(page);
  await page.goto('/');
  await target(page, 'Lotin 1995').click();
  await page.getByRole('tab', { name: 'Fayllar' }).click();
  await page.getByTestId('file-input').setInputFiles(join(DOCS, 'writer.docx'));
  const item = page.getByTestId('file-item');
  await expect(item.getByTestId('file-status')).toHaveText('Tayyor');
  const [download] = await Promise.all([page.waitForEvent('download'), item.getByTestId('download').click()]);
  expect(download.suggestedFilename()).toBe('writer-lat.docx');
  const zip = ZipArchive.read(new Uint8Array(readFileSync(await download.path())));
  expect(zip.text(zip.get('word/document.xml')!)).toContain('<w:rPr><w:b/></w:rPr><w:t>SHAH</w:t>');
  expect(zip.text(zip.get('word/footnotes.xml')!)).toContain('Izoh: gʻalaba va chiroq.');
  expect(zip.text(zip.get('word/comments.xml')!)).toContain('w:author="Муаллиф"');
  expect(problems).toEqual([]);
});

test('a batch of files, downloaded as one ZIP', async ({ page }) => {
  await page.goto('/');
  await page.getByRole('tab', { name: 'Fayllar' }).click();
  const files = ['writer.odt', 'calc.xlsx', 'impress.pptx', 'writer.rtf', 'writer.epub'];
  await page.getByTestId('file-input').setInputFiles(files.map(f => join(DOCS, f)));
  await expect(page.getByTestId('file-status')).toHaveText(files.map(() => 'Tayyor'));
  const [download] = await Promise.all([page.waitForEvent('download'), page.getByTestId('download-all').click()]);
  expect(download.suggestedFilename()).toBe('uztranslit-new.zip');
  const zip = ZipArchive.read(new Uint8Array(readFileSync(await download.path())));
  expect(zip.entries.map(e => e.name).sort()).toEqual(files.map(f => f.replace('.', '-new.')).sort());
  for (const e of zip.entries) expect(ZipArchive.isZip(zip.data(e)) || e.name.endsWith('.rtf')).toBe(true);
});

test('a large text file is split across workers and converts exactly', async ({ page }) => {
  const line = 'ШАҲАР маркази www.example.uz/йўл Исҳоқ кўчаси, мўъжиза ва объект; Ёз фасли.\n';
  const text = line.repeat(Math.ceil((6 << 20) / (line.length * 2)));
  const dir = mkdtempSync(join(tmpdir(), 'uzt-e2e-'));
  writeFileSync(join(dir, 'katta.txt'), text);
  await page.goto('/');
  await target(page, 'Lotin 1995').click();
  await page.getByRole('tab', { name: 'Fayllar' }).click();
  await page.getByTestId('file-input').setInputFiles(join(dir, 'katta.txt'));
  await expect(page.getByTestId('file-status')).toHaveText('Tayyor', { timeout: 60000 });
  const [download] = await Promise.all([page.waitForEvent('download'), page.getByTestId('download').click()]);
  const U = await wasmEngine();
  expect(readFileSync(await download.path(), 'utf8')).toBe(U.convert(text, 'cyr', 'lat'));
});

test.describe('without WebAssembly', () => {
  // requests answered by the service worker bypass routing, so keep it out of this test
  test.use({ serviceWorkers: 'block' });

  test('the JavaScript build of the engine takes over', async ({ page, context }) => {
    await context.route('**/*.wasm', r => r.abort());
    await page.goto('/');
    await page.getByTestId('source').fill('Объект, компьютер, ШАҲАР');
    await expect(page.getByTestId('result')).toHaveValue('Obyekt, kompyuter, ŞAHAR');
    await expect(page.getByTestId('engine')).toContainText('JavaScript');
  });
});

test('fits a phone screen without horizontal scrolling', async ({ page }) => {
  await page.setViewportSize({ width: 375, height: 812 });
  await page.goto('/');
  await page.getByRole('tab', { name: 'Fayllar' }).click();
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
  expect(overflow).toBeLessThanOrEqual(0);
});

test('English interface', async ({ page }) => {
  await page.goto('/');
  await page.getByRole('button', { name: 'Interfeys tili' }).click();
  await expect(page.getByRole('tab', { name: 'Files' })).toBeVisible();
  await expect(page.locator('html')).toHaveAttribute('lang', 'en');
});

test('works offline after the first visit', async ({ page, context }) => {
  test.setTimeout(90000);
  await page.goto('/');
  await page.evaluate(async () => { await navigator.serviceWorker.ready; });
  // the service worker fetches the app after activating; wait until every prefetch file is in its cache
  const missing = () => page.evaluate(async () => {
    const manifest = await (await fetch('ngsw.json', { cache: 'no-store' })).json() as { assetGroups: Array<{ name: string; urls: string[] }> };
    const want = manifest.assetGroups.find(g => g.name === 'app')!.urls;
    const have = new Set<string>();
    for (const key of await caches.keys()) for (const r of await (await caches.open(key)).keys()) have.add(new URL(r.url).pathname);
    return want.filter(u => !have.has(u));
  });
  await expect.poll(missing, { timeout: 60000 }).toEqual([]);
  await context.setOffline(true);
  await page.reload();
  await page.getByTestId('source').fill('Toshkent');
  await expect(page.getByTestId('result')).toHaveValue('Toşkent');
});
