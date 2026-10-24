# UzTranslit Office add-in (Office.js)

For the Office versions that cannot run the VBA module: **Office on the web, Office on Mac and iPad, Microsoft 365**
(Word, Excel, PowerPoint; Office 2016 and later on Windows too). A **UzTranslit ▸ Alifbo** button on the Home tab opens
a task pane: source script (Avto, Кирилл, Lotin 1995, Yangi lotin), target script, the selection or the whole
document, plain or typographic apostrophe. The task pane speaks Uzbek, Russian or English.

The task pane is served by the web site at **https://latin.jaybi.uz/office/** (`web/scripts/sync-core.mjs` stages it
from this folder). Until the `latin.jaybi.uz` DNS record exists (docs/DNS.md), use `manifest-github-pages.xml`,
which points at https://kool277.github.io/uz-latn-kiril/office/.

## What it converts

| Host | What | Formatting |
|---|---|---|
| Word (WordApi 1.3+) | body, headers and footers, or the selection | kept word by word; change tracking is paused during the run |
| Excel (ExcelApi 1.1+) | text cells of the selection (its used part) or of every sheet | formulas, numbers and dates untouched; a converted value that would read as a number, date or formula keeps the apostrophe prefix that makes it text |
| PowerPoint (PowerPointApi 1.4+) | text shapes of every slide, or the selected shapes | kept word by word |
| any older host | the selected text | plain text |

Every word (run of non-whitespace characters) is converted on its own and replaced only if it changes. No rule of
the converter looks across whitespace, so this gives exactly the conversion of the whole text (the tests check it on
the 20,000-case differential corpus). Office.js gives no access to formatting inside a word: a word whose letters are
formatted differently takes the formatting of its first letter (the VBA macros keep it), and Excel's rich text in a
cell becomes one formatting. URLs and e-mail addresses stay. Auto detection runs once for the whole selection or
document.

## Sideload (try it without a store)

* **Office on the web** (Word, Excel, PowerPoint): *Home ▸ Add-ins ▸ More add-ins ▸ My add-ins ▸ Upload My Add-in*,
  choose `manifest.xml` (or download it from the site: `downloads/uztranslit-office-addin.xml`).
* **Windows**: put the manifest in a shared network folder, add that folder in *File ▸ Options ▸ Trust Center ▸
  Trust Center Settings ▸ Trusted Add-in Catalogs* (tick *Show in Menu*), restart Office, then *Home ▸ Add-ins ▸
  Advanced ▸ Shared Folder*.
* **Mac**: copy the manifest to `~/Library/Containers/com.microsoft.Word/Data/Documents/wef/` (Excel:
  `com.microsoft.Excel`, PowerPoint: `com.microsoft.Powerpoint`; create `wef` if missing), restart, then
  *Home ▸ Add-ins*.
* **iPad, and a whole organisation**: Microsoft 365 admin center ▸ *Settings ▸ Integrated apps ▸ Upload custom apps*.

## Development

```
node platforms/office-addin/build.mjs              # manifest.xml + manifest-github-pages.xml from manifest.template.xml
node platforms/office-addin/build.mjs --check      # are the committed manifests current?
node platforms/office-addin/test/run.mjs           # logic against fake Word / Excel / PowerPoint (test/fakes.mjs)
cd web && npm run build && npx playwright test test/e2e/office-addin.spec.ts   # the served task pane in Chromium
```

`src/` is ES5 on purpose: Office 2016 and 2019 on Windows may run task panes in Internet Explorer 11. Office.js
must come from Microsoft's CDN; the task pane's Content-Security-Policy allows that origin and nothing else for
scripts. Microsoft's validator (`npx office-addin-manifest validate manifest.xml`, which sends the manifest to
Microsoft) reports both manifests valid for Word, Excel and PowerPoint on Windows, Mac, the web and iPad.

What the tests cannot show: how a real Office host behaves. The fakes follow Office.js where it is strict (no
property before `load()` + `sync()`, ranges that follow edits, a replacement taking its first letter's
formatting), and the code only uses documented APIs behind requirement-set checks.
