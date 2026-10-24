import { expect, Page, test } from '@playwright/test';

// The Office add-in's task pane as the site serves it (/office/taskpane.html), with its real HTML, CSP and scripts.
// Office.js is replaced at its CDN address: by nothing (opened outside Office), or by a stand-in host whose selected
// text is plain (the path every Office version supports).
const OFFICE_JS = 'https://appsforoffice.microsoft.com/lib/1/hosted/office.js';

function watch(page: Page): string[] {
  const problems: string[] = [];
  page.on('console', m => { if (/Content.Security.Policy|Refused to/i.test(m.text())) problems.push(m.text()); });
  page.on('pageerror', e => problems.push(e.message));
  return problems;
}

const fakeOffice = (host: string, language: string, text: string) => `
  window.Office = {
    HostType: { Word: 'Word', Excel: 'Excel', PowerPoint: 'PowerPoint' },
    CoercionType: { Text: 'text' },
    AsyncResultStatus: { Succeeded: 'succeeded' },
    context: {
      host: ${JSON.stringify(host)},
      displayLanguage: ${JSON.stringify(language)},
      requirements: { isSetSupported: function () { return false; } },
      document: {
        text: ${JSON.stringify(text)},
        getSelectedDataAsync: function (type, cb) { cb({ status: 'succeeded', value: this.text }); },
        setSelectedDataAsync: function (t, o, cb) { this.text = t; cb({ status: 'succeeded' }); }
      }
    },
    onReady: function (cb) { setTimeout(function () { cb({ host: ${JSON.stringify(host)} }); }, 0); }
  };`;

test('task pane outside Office says where it belongs', async ({ page }) => {
  const problems = watch(page);
  await page.route(OFFICE_JS, r => r.abort());
  await page.goto('/office/taskpane.html');
  await expect(page.getByRole('status')).toContainText('Word, Excel yoki PowerPoint');
  await expect(page.getByRole('button', { name: 'Oʻgirish' })).toBeDisabled();
  expect(problems).toEqual([]);
});

test('task pane converts the selection, in Russian when Office speaks Russian', async ({ page }) => {
  const problems = watch(page);
  await page.route(OFFICE_JS, r => r.fulfill({ contentType: 'application/javascript', body: fakeOffice('PowerPoint', 'ru-RU', 'Ишоқ ва шаҳар') }));
  await page.goto('/office/taskpane.html');
  await page.getByLabel('Алфавит результата').selectOption('new');
  await page.getByRole('button', { name: 'Преобразовать' }).click();
  await expect(page.getByRole('status')).toContainText('Преобразовано слов: 3 (Кириллица → Новая латиница)');
  await expect(page.getByRole('status')).toContainText('без форматирования');
  expect(await page.evaluate(() => (window as unknown as { Office: { context: { document: { text: string } } } }).Office.context.document.text)).toBe('Işoq va şahar');
  expect(problems).toEqual([]);
});

test('task pane: the manifest the site links to points at the task pane', async ({ request }) => {
  const manifest = await (await request.get('/downloads/uztranslit-office-addin.xml')).text();
  expect(manifest).toContain('<SourceLocation DefaultValue="https://latin.jaybi.uz/office/taskpane.html"/>');
  expect((await request.get('/office/taskpane.html')).ok()).toBe(true);
  expect((await request.get('/office/commands.html')).ok()).toBe(true);
});
