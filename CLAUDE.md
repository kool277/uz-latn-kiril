# CLAUDE.md — standing rules for this repository

UzTranslit converts Uzbek text between Cyrillic (`cyr`), Latin 1995 (`lat`) and Latin 2026 (`new`: Ö Ğ Ş Ç per law OʻRQ-1184, 21 Oct 2026).
`CLAUDE_CODE_PROMPT.md` is the phased plan (all phases built; releases come from a `v*` tag via `release.yml`).

## Source of truth
- `spec/SPEC.md` defines the algorithm; `spec/fixtures.json` defines correctness (216 checks). Both are versioned together.
- A conversion rule is changed **only** by editing the spec and fixtures first, then every port. Never patch one port.
- Ports: `core/js` (reference), `core/python`, `core/wasm` (AssemblyScript → WebAssembly, plus the same engine translated
  to plain JS by wasm2js), `office-vba` (VBA 5–7, also feeds `libreoffice/` through `tools/make_lo_basic.py`),
  `platforms/android` (Kotlin), `platforms/ios` (Swift), `platforms/qt-desktop` (C++/Qt 6). The dictionary (SPEC §6)
  is copied in every one of them; `platforms/office-addin` (Office.js) uses `core/js`; `platforms/office-installer`
  (PyInstaller exe) installs `office-vba` with its ribbon into Word/Excel.

## How to test
```
tools/test_all.sh                      # every suite this machine can run; must end with ALL SUITES GREEN
node core/js/test.js
python3 core/python/test_uztranslit.py
cd core/wasm && npm run build && node test.mjs     # fixtures + differential test vs core/js + segment test, both builds
cd web && npm run test:engine          # web engine: fixtures, every document format, LibreOffice round-trips if installed
cd web && npm test                     # Angular unit tests (vitest, jsdom)
cd web && npm run build && npm run e2e # Playwright against the production build (npx playwright install chromium once)
python3 tools/make_lo_basic.py --test && python3 tools/lo_run_macro.py Standard.UzTest.RunAll build/lo-test/result.txt
python3 tools/lo_run_macro.py UzOffice.UzCheck.Run build/lo-test/office.txt   # whole Office module compiles, UzSelfTest
python3 tools/lo_extension_test.py     # both .oxt end to end in Writer/Calc/Impress (+ Calc formulas via My Macros)
python3 tools/vba_lint.py office-vba/*.bas     # undeclared names etc.: one would break every macro in real VBA
python3 tools/test_add_ribbon.py       # Office ribbon injection (tools/add_ribbon.py)
python3 platforms/office-installer/test_installer.py   # Office installer vs fake Word/Excel (exe: office-installer.yml)
node platforms/office-addin/test/run.mjs       # add-in logic against fake Word/Excel/PowerPoint
python3 tools/test_mine_dictionary.py  # dictionary miner (tools/mine_dictionary.py)
platforms/android: ./gradlew test assembleDebug (release: README ▸ Signing) · platforms/ios/scripts/test.sh · platforms/qt-desktop: README (Docker)
python3 tools/build_oxt.py             # rebuilds both .oxt files (reproducible: commit them with their sources)
python3 tools/make_doc_fixtures.py     # regenerates web/test/fixtures/docs/* with LibreOffice
```
A change is not done until every suite prints `0 failed`. The web app needs Node 22.22+/24.15+/26+ (`.nvmrc`: 24);
Angular refuses odd Node versions.
The LibreOffice runs use throwaway profiles under `build/`; never point them at the real `~/.config/libreoffice`
profile — installing the test library there replaces the user's My Macros ▸ Standard.

## Porting rules
- Keep SPEC §5 helper names and the index-based scanner in every language; no regex-only implementations.
- All relevant characters are in the BMP, so UTF-16 code-unit iteration (JS, Qt, Swift UTF-16 view, Kotlin) is fine.
- Empty-string/undefined guards: `"".indexOf("")` is 0 in JS — every helper must treat "no character" explicitly.
- Basic is case-insensitive: never declare `n` and `N` in one scope. Single-line `If … Then Sub a, b Else Sub c, d` is invalid in LibreOffice Basic — use block `If`.
- Non-ASCII in `office-vba/*.bas` and `libreoffice/UzTranslitLO.bas` only via `ChrW`/`U("hex hex …")`; they stay pure
  ASCII, and `office-vba/*.bas` are stored with CRLF (`.gitattributes`): the VBA editor's Import needs both.
- Rich-text hosts: a paragraph is converted as one string and split back over its runs/portions with
  `UzSplitConvert` / `_split` (linear: no rule looks across whitespace). LibreOffice replaces a portion without
  copying attributes (`UzLO_ReplacePortion`: Writer inserts after the first character, cells/shapes at the end) inside
  locked controllers and one undo context. Word never rewrites fields, pictures, content controls or special marks
  and puts bookmarks back (`UzWord_SetText`).
- LibreOffice cannot call an extension's Basic functions from Calc cells: formulas need the module in My Macros.
- Default options: okina U+02BB, tutuq U+02BC, dropHardSignAfterO, tsFinal, dictionary, skipUrls (where tokenisation is possible).
- `core/wasm/build-js.mjs` recompiles the AssemblyScript source with `--disable bulk-memory` for wasm2js; both builds
  must pass `core/wasm/test.mjs`. AssemblyScript string literals cannot contain U+2028/U+2029 (use char codes).

## Web app (`web/`, Angular 22, zoneless, signals)
- `src/app/engine/` is framework-free and runs inside Web Workers: format handlers turn a file into paragraphs of
  segments (`text-model.ts`), the WASM engine converts whole paragraphs with `convertSegments`, and only the
  segments' source ranges are rewritten — markup, styles and media stay byte-identical. Add a format by writing a
  handler that returns `Prepared` and wiring it in `document.ts`; add a test in `web/test/engine`.
- `services/engine.service.ts` runs one worker per core (max 8) plus one for the text editor; the WASM module is
  compiled once and posted to workers. Large .txt/.csv files are cut at line feeds and converted on all workers.
- `scripts/sync-core.mjs` (run by prestart/prebuild/pretest) copies the core/wasm builds, `spec/fixtures.json` and
  the Office/LibreOffice downloads into gitignored folders; never edit `src/generated`, `public/wasm`, `public/downloads`.
- Security: `src/index.html` carries a strict CSP (only 'self', `wasm-unsafe-eval`, Trusted Types); `main.ts`
  installs the only Trusted Types policy (same-origin `.js` script URLs). Never use `innerHTML`/`bypassSecurityTrust*`,
  never load third-party resources; `scripts/csp-hash.mjs` (postbuild) allows Angular's inline import map by hash.
- URLs inside the app are relative (`wasm/…`, `downloads/…`): the site runs under `/` and under `/<repo>/`.
- UI strings live in `src/app/i18n/`: `uz.ts` (Latin 1995, default and reference), `uz-new.ts` (Latin 2026), `ru.ts`, `en.ts`.
  A new key goes into all four (TypeScript enforces it; `app.spec.ts` checks placeholders match). Make `uz-new` strings by
  converting the `uz` ones with the engine (lat → new, `{placeholders}` protected), then review: examples of the old
  spelling (Isʼhoq → Ishoq) must stay. Russian counts use «символов: N» so no plural forms are needed.
  Every user-facing error is an `err.*` key. `?lang=uz|uz-new|ru|en` picks the language; a Russian-first browser gets `ru`.
- Search: `scripts/seo.mjs` (postbuild) writes `/`, `/ru/`, `/en/` with their own title/description (`doc.*` keys),
  keywords, hreflang, Open Graph, JSON-LD and static text in `<app-root>`; the app takes `ru`/`en` from the path.
  Keep `public/sitemap.xml` in step with its pages.

## Conventions
- UI language: Uzbek (Latin), English fallback; the web app also has Uzbek Latin 2026 and Russian (asked for by the
  user on 2026-10-24). Labels: Кирилл / Lotin 1995 / Yangi lotin (Кириллица / Латиница 1995 / Новая латиница in Russian).
- Conventional commits; one phase per commit; update `README.md` platform table with every platform change.
- Web: deployed by `.github/workflows/deploy-pages.yml` after CI passes on main (custom domain: `docs/DNS.md`);
  keep `web/public/CNAME`.
