# CLAUDE.md — standing rules for this repository

UzTranslit converts Uzbek text between Cyrillic (`cyr`), Latin 1995 (`lat`) and Latin 2026 (`new`: Ö Ğ Ş Ç per law OʻRQ-1184, 21 Oct 2026).
`CLAUDE_CODE_PROMPT.md` is the phased plan (web done; Android, iOS, Qt, Office add-in, releases to come).

## Source of truth
- `spec/SPEC.md` defines the algorithm; `spec/fixtures.json` defines correctness (212 checks). Both are versioned together.
- A conversion rule is changed **only** by editing the spec and fixtures first, then every port. Never patch one port.
- Ports: `core/js` (reference), `core/python`, `core/wasm` (AssemblyScript → WebAssembly, plus the same engine translated
  to plain JS by wasm2js), `office-vba` (VBA 5–7, also feeds `libreoffice/` through `tools/make_lo_basic.py`).
  Planned under `platforms/`: android (Kotlin), ios (Swift), qt-desktop (C++), office-addin (Office.js).

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
python3 tools/build_oxt.py             # rebuilds both .oxt files
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
- Non-ASCII in `office-vba/UzTranslit.bas` only via `ChrW`/`U("hex hex …")`; the module must stay pure ASCII.
- Rich-text hosts: convert runs/portions (Word runs, LibreOffice text portions, PowerPoint `Runs`), restore character attributes after replacing a portion (`UzLO_ReplacePortion` / `_replace_portion`).
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
- UI strings live in `services/i18n.service.ts` (uz first, en second); every user-facing error is an `err.*` key.

## Conventions
- UI language: Uzbek (Latin), English fallback. Labels: Кирилл / Lotin 1995 / Yangi lotin.
- Conventional commits; one phase per commit; update `README.md` platform table with every platform change.
- Web: deployed by `.github/workflows/deploy-pages.yml` after CI passes on main (custom domain: `docs/DNS.md`);
  keep `web/public/CNAME`.
