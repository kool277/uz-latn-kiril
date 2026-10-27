# UzTranslit — Oʻzbek alifbo konvertori

Converts Uzbek text between **Cyrillic (1940)**, **Latin 1995** (Oʻ Gʻ Sh Ch) and the **Latin alphabet of 2026**
adopted by law **OʻRQ-1184 (21 October 2026)**: **Oʻ → Ö, Gʻ → Ğ, Sh → Ş, Ch → Ç**, `ng` dropped as a letter, tutuq belgisi ʼ kept — 28 letters + ʼ, in force six months after publication.

All six directions, with the rules that matter: е/э, ц → s/ts, ъ/ь, йў vs ё, `sʼh` ↔ `sh`, casing of digraphs (ШАҲАР → SHAHAR / Şahar), a loanword dictionary (obyekt → объект, kompyuter → компьютер, sirk → цирк …), auto-detection, URL/e-mail protection.

## What is in the kit

| Part | Path | Status |
|---|---|---|
| Specification + 238-check conformance corpus | `spec/` | source of truth |
| JavaScript core (browser/Node, UMD) | `core/js/uztranslit.js` | 238/238 ✔ |
| Python core + CLI | `core/python/uztranslit.py` | 238/238 ✔ |
| WebAssembly core (AssemblyScript) + the same engine as plain JS (wasm2js) | `core/wasm/` | 238/238 ✔ both builds; identical to the JS core on 40,000 random conversions per build in CI (1.2M checked once) |
| Web app for **https://latin.jaybi.uz** — Angular 22, WebAssembly on every CPU core, text **and documents**, PWA/offline | `web/` | 238/238 ✔ both engines · 551 engine tests · 19 Playwright tests |
| MS Office macro module (Word/Excel/PowerPoint 97 → 2026, VBA 5–7) | `office-vba/UzTranslit.bas` | engine executed in LibreOffice Basic VBA mode: 214/214 ✔, 3,500 differential ✔; document macros compiled + linted (Office itself not in CI) |
| Desktop (Qt 6): Windows installer, macOS dmg, Linux AppImage — editor with live conversion, text/Markdown/SRT/HTML/XML files, folder batch, tray clipboard actions, `uztranslit` CLI | `platforms/qt-desktop/` | C++ core 238/238 ✔, 22,000 differential ✔, 7 ctest suites (CLI, GUI offscreen, documents, translations); packages built in CI, unsigned |
| Office ribbon tab (2007+): `UzTranslitRibbon.bas` + `office-vba/ribbon/`, put into a .dotm/.xlam/.ppam by `tools/add_ribbon.py` | `office-vba/ribbon/` | injection tested on Word/Excel/PowerPoint files; `UzSelfTest` 29/29 in CI |
| Office installer for Windows: `UzTranslit-<version>-Office-Setup.exe` (PyInstaller) builds `UzTranslit.dotm` / `UzTranslit.xlam` with Word and Excel through COM, adds the ribbon, puts them into STARTUP / XLSTART | `platforms/office-installer/` | 28 checks against fake Word/Excel; exe built and started on Windows in CI (no Office in CI) |
| Office add-in (Office.js) for Word, Excel, PowerPoint on the web, Mac, iPad and Microsoft 365, served at latin.jaybi.uz/office | `platforms/office-addin/` | manifests valid (Microsoft validator); logic tested against fake hosts + the 20,000-case corpus; task pane tested in Chromium |
| LibreOffice extension (menu Tools ▸ UzTranslit) | `libreoffice/uztranslit-libreoffice.oxt` | installed + e2e-tested in Writer/Calc/Impress ✔ |
| LibreOffice Basic module / Python edition | `libreoffice/UzTranslitLO.bas`, `uztranslit-libreoffice-python.oxt` | ✔ / needs Python provider |
| Android 7+ — Kotlin core + Compose app: live converter, *Process text* menu on selected text, share sheet, .txt files, Quick Settings tile | `platforms/android/` | Kotlin core 238/238 ✔, 20,000 differential ✔, 290 JVM tests; signed release APK + bundle built in CI and started on an emulator |
| iOS / iPadOS / macOS — Swift package `UzTranslitCore`, SwiftUI app with Share and Action extensions, macOS app with a Services menu item | `platforms/ios/` | Swift core 238/238 ✔, 20,000 differential ✔ (Linux, CI); apps built unsigned on macOS in CI — signing/TestFlight need your Apple team (`platforms/ios/README.md`) |
| Claude Code master prompt (Android, iOS, Qt 6, Office.js add-in, CI, releases) | `CLAUDE_CODE_PROMPT.md` + `CLAUDE.md` | run it |

## Downloads

Every [release](https://github.com/kool277/uz-latn-kiril/releases/latest) is built by `.github/workflows/release.yml`
from a `v*` tag after every suite passes: Windows installer, macOS dmg, Linux AppImage, Android APK, Office installer, Office
macros and ribbon kit, Office add-in manifest, LibreOffice extensions and the web app as a zip, with `SHA256SUMS.txt`
(`sha256sum -c SHA256SUMS.txt --ignore-missing`).

## Quick start

```bash
node core/js/test.js                              # 238 passed
python3 core/python/test_uztranslit.py            # 238 passed
echo "O'zbekiston Respublikasi" | python3 core/python/uztranslit.py --to new      # Özbekiston Respublikasi
echo "Toshkent shahri" | python3 core/python/uztranslit.py --to cyr              # Тошкент шаҳри
```

```js
const U = require('./core/js/uztranslit.js');
U.convert("Toshkent shahri, Is'hoq", 'lat', 'new');   // "Toşkent şahri, Ishoq"
U.convert('Ўзбекистон', 'cyr', 'lat');                // "Oʻzbekiston"
U.convert('Özbekiston', 'auto', 'cyr');               // "Ўзбекистон"
U.detect('Toşkent');                                  // "new"
```

## Web app (latin.jaybi.uz)

Type or paste text — or drop files. Everything runs in the browser: the WebAssembly engine runs in a pool of
Web Workers (one per CPU core, up to 8), so nothing is uploaded and large batches use the whole machine.
Interface languages: Oʻzbekcha (Latin 1995, default), Özbekça (Latin 2026), Русский, English — `?lang=ru` etc.

| Files | What changes | What stays exactly as it was |
|---|---|---|
| Word, Excel, PowerPoint (docx/xlsx/pptx, macro and template variants) | text runs, footnotes, headers/footers, comments, text boxes, SmartArt, chart labels, alt text, embedded workbooks, spell-check language (uz-Cyrl ↔ uz-Latn) | every other byte: styles, fonts, pictures, formulas, numbers, field codes, comment authors, sheet names |
| LibreOffice (odt/ods/odp/odg, flat fodt/fods/fodp/fodg) | the same | the same |
| RTF, EPUB, FB2, HTML/XHTML, XML, SVG | text, titles, alt/title attributes, metadata | markup, scripts, styles, code, URLs, `translate="no"` |
| TXT, CSV, Markdown, JSON, SRT/VTT/ASS | text; JSON string values (not keys) | encoding and BOM (legacy Windows-1251/KOI8-R/DOS-866 files become UTF-8), line endings, code blocks, link targets, timings, tags |

A word split across differently formatted runs (**ШАҲ**АР) still converts as one word (**SHAH**AR in Latin 1995, **ŞAH**AR in Latin 2026):
whole paragraphs go through the engine and each run gets its share back. PDF and the old binary .doc/.xls/.ppt
are not supported (the app says so); save those as docx/xlsx/pptx first.

Security: a strict Content-Security-Policy (own origin only, `wasm-unsafe-eval`, Trusted Types), subresource
integrity, no third-party resources, no `innerHTML`, ZIP-bomb and size limits, XML parsed without entity expansion.

```bash
cd web
npm ci
npm start                # http://localhost:4200 (builds core/wasm on first run)
npm run test:engine      # engine + document formats (+ LibreOffice round-trips when soffice is installed)
npm test                 # Angular unit tests
npm run build && npx playwright install chromium && npm run e2e
```

Deployment: `.github/workflows/deploy-pages.yml` publishes to GitHub Pages after CI passes on `main`;
`docs/DNS.md` sets up the `latin.jaybi.uz` domain. Deep links: `https://latin.jaybi.uz/?text=Toshkent&to=cyr`.

## Office and LibreOffice

* `docs/OFFICE_INSTALL.md` — import the `.bas`, run `UzSelfTest`, use `UzTranslit_AutoToNew` & co., `=UzConvert(A1,"lat","new")` in Excel.
* `docs/LIBREOFFICE_INSTALL.md` — install the `.oxt` or import the Basic module; `=UZCONVERT(A1;"lat";"new")` in Calc.

## Building the rest with Claude Code

```
claude          # from the repository root
> (paste CLAUDE_CODE_PROMPT.md)
```
`CLAUDE.md` keeps the standing rules (spec first, every port passes the fixtures, formatting-preserving edits).

## Rules worth knowing (see `spec/SPEC.md`)

* Cyrillic е → `ye` at word start / after a vowel / after ъ ь, else `e`; ц → `ts` after a vowel, else `s`; ъ → ʼ (dropped before е ё ю я and after ў); ь dropped, but ьо → `yo` (батальон → batalyon); сентябрь, октябрь → `sentabr`, `oktabr`.
* 1995 Latin `sʼh` (Isʼhoq) becomes plain `sh` in 2026 Latin (Ishoq) because Ş makes it unambiguous; the reverse inserts ʼ again.
* `yoʻl` → йўл, `tayyor` → тайёр, `oʻtsa` stays ўтса while `militsiya` → милиция, `abzats` → абзац.
* Latin → Cyrillic writes the Cyrillic spelling back: word-initial `ts` → ц (`tsirk` → цирк), and the loanword dictionary
  restores ц, ь and ъ (`albom` → альбом, `iyul` → июль, `moʻjiza` → мўъжиза); a final ь goes before a suffix as in Cyrillic
  texts (`iyuldagi` → июлдаги, `avtomobillar` → автомобиллар).
* Casing: ШАҲАР → SHAHAR, Шаҳар → Shahar, Ş alone → Sh.
* The 2026 *imlo qoidalari* are not published yet; the few open points (ўъ, `ng`) are options, documented in SPEC §7.

MIT License.
