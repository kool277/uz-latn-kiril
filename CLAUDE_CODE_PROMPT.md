# UzTranslit — master prompt for Claude Code

> Paste everything below the line into Claude Code (`claude`) from the root of this repository,
> or run `claude "$(cat CLAUDE_CODE_PROMPT.md)"`. Work phase by phase; each phase ends with a
> green test run and a commit. `CLAUDE.md` in the repo root carries the standing rules.

---

You are building **UzTranslit**, a family of converters for Uzbek text between three scripts:

* `cyr` — Uzbek Cyrillic (1940),
* `lat` — Uzbek Latin 1995 (Oʻ Gʻ Sh Ch Ng + ʼ),
* `new` — Uzbek Latin 2026 under law **OʻRQ-1184 of 21 Oct 2026**: **Oʻ→Ö, Gʻ→Ğ, Sh→Ş, Ch→Ç**, `ng` is no longer a letter, tutuq belgisi ʼ (U+02BC) stays. 28 letters + ʼ. The law takes effect six months after publication (≈ late April 2027), so people need all six directions for years.

## What already exists (do not rewrite, extend)

```
spec/SPEC.md            the algorithm — the ONLY source of truth for conversion rules
spec/alphabets.json     letter tables
spec/fixtures.json      212 conformance checks; every port must pass them (cases, roundtrips, detect)
core/js/uztranslit.js   reference implementation (UMD, zero deps)      ✔ 212/212   node core/js/test.js
core/python/uztranslit.py  Python port + CLI                           ✔ 212/212   python3 core/python/test_uztranslit.py
office-vba/UzTranslit.bas  VBA 5/6/7 module for Word/Excel/PowerPoint 97–2026  ✔ engine executed in LibreOffice Basic (VBA mode): 210/210
libreoffice/UzTranslitLO.bas             generated Basic module (engine + UNO UI)   — tools/make_lo_basic.py
libreoffice/uztranslit-libreoffice.oxt   extension (Basic edition, menu Tools ▸ UzTranslit) ✔ e2e-tested in Writer/Calc/Impress
libreoffice/uztranslit-libreoffice-python.oxt  same, Python edition (needs libreoffice-script-provider-python)
web/                    GitHub Pages site for https://latin.jaybi.uz (index.html, uztranslit.js, CNAME, PWA files)
tools/                  make_lo_basic.py, build_oxt.py, lo_run_macro.py (headless LibreOffice test runner)
```

## Non-negotiable rules

1. **Rules live in `spec/`.** Never change a conversion rule in one port. Change `spec/SPEC.md` + `spec/fixtures.json` first, then update every port, then run every suite.
2. **Every port is a faithful port of SPEC §5** (index-based scanner, same helper names: `isCyr`, `isLat`, `isApos`, `nextLetterIsUpper`, `caseOut`, `cyrToLatin`, `latinToCyrScan`, `convertWordWithDict`, `latToNew`, `newToLat`, `detect`). No regex-only shortcuts, no "close enough" tables.
3. **Every port ships a fixture runner** that loads `spec/fixtures.json` (copy it into the platform's test resources at build time, never hand-copy cases) and fails the build on any mismatch.
4. Default options everywhere: okina `ʻ` U+02BB, tutuq `ʼ` U+02BC, `dropHardSignAfterO=true`, `tsFinal=true`, `dictionary=true`, `skipUrls=true` (where the platform can tokenise). Offer an "ASCII apostrophe" switch in every UI.
5. Text handling: never lose user text; non-letters pass through untouched; preserve formatting wherever the host has rich text (runs/portions, not whole paragraphs).
6. Apostrophes on input: accept `' ʻ ʼ ‘ ’ ` ´`. Legacy draft glyphs `Ō ō Õ õ` are read as Ö ö, never written.
7. Commit after each green phase with a conventional message. Keep PR-sized diffs.
8. Keep the UI language Uzbek (Latin) with English fallbacks; no machine-translated Russian unless asked.

## Phase 0 — bootstrap (30 min)

* `git init`, `.gitignore` (node, python, gradle, xcode, build/), `LICENSE` (MIT), top-level `README.md` (exists — keep it current).
* Add `tools/test_all.sh`: runs `node core/js/test.js`, `python3 core/python/test_uztranslit.py`, and — if `soffice` is on PATH — `python3 tools/make_lo_basic.py --test && python3 tools/lo_run_macro.py Standard.UzTest.RunAll build/lo-test/result.txt` and asserts "0 failed".
* GitHub Actions `ci.yml`: ubuntu job running `tools/test_all.sh` with `apt-get install libreoffice-core libreoffice-writer libreoffice-calc python3-uno`.
* Verify all suites are green. Commit `chore: bootstrap repo + CI`.

## Phase 1 — web (latin.jaybi.uz)

* `web/` is complete and tested in the browser (`index.html` loads `uztranslit.js`, PWA, CNAME). Add `deploy-pages.yml` (GitHub Actions, `actions/deploy-pages`, publish the `web/` directory; copy `core/js/uztranslit.js` into `web/` in the workflow so the site always ships the tested core).
* Write `docs/DNS.md`: `latin` CNAME → `<user>.github.io`, enable "Enforce HTTPS" after the certificate is issued, `CNAME` file must stay in `web/`.
* Add `web/sitemap.xml`, `robots.txt`, Open Graph tags, and a "Yuklab olish / Downloads" section listing the Office module, the LibreOffice .oxt and (later) Android/iOS/desktop builds — links to GitHub Releases.
* Add an `?text=…&to=new` deep link test and a Playwright smoke test (`web/test/`) that types "O'zbekiston shahri" and asserts "Özbekiston şahri".

## Phase 2 — Android

* `platforms/android/` — Kotlin, Gradle (KTS), minSdk 24, targetSdk latest, Jetpack Compose, Material 3, dynamic colour.
* Module `core` (pure Kotlin, no Android deps): `UzTranslit.kt` = port of SPEC §5 with the same function names; `UzDictionary.kt` holds SPEC §6; unit test `FixturesTest.kt` reads `spec/fixtures.json` copied by a Gradle `copy` task into `src/test/resources`.
* Module `app`:
  * Main screen: source segmented control (Avto / Кирилл / Lotin 1995 / Yangi lotin), target, swap, live conversion, copy, share, paste, clear, char/word counts, ASCII-apostrophe toggle, dark theme.
  * `ACTION_PROCESS_TEXT` activity ("UzTranslit bilan oʻgirish") so selected text in any app can be converted in place (return the result in `EXTRA_PROCESS_TEXT` when the caller allows replacement).
  * Share-sheet target for `text/plain` and `.txt`/`.md`/`.srt`/`.csv` files; converted file saved via SAF with the original name + `-new`.
  * Quick Settings tile that converts the clipboard to the preferred target.
  * Settings: default target, apostrophe style, dictionary on/off, `dropHardSignAfterO`.
  * Localisation: `values-uz`, `values-ru`, `values` (en).
* CI: `android.yml` builds a debug APK and runs unit tests; attach APK to releases.

## Phase 3 — iOS (Swift)

* `platforms/ios/` — Swift Package `UzTranslitCore` (pure Swift, `String`/`Character` based port with the SPEC helper names; `Fixtures.json` bundled as a test resource via `Bundle.module`), XCTest `FixturesTests` must pass 212/212.
* App target (SwiftUI, iOS 16+): same screen as Android, `ShareLink`, paste button, haptics, Dynamic Type, dark mode.
* **Share Extension** (`NSExtensionActivationSupportsText`, `public.plain-text`, `public.file-url` for .txt) and an **Action Extension** that returns the converted text to the host app.
* macOS Catalyst / native macOS target reusing the package; a Services menu item "Convert to Yangi lotin".
* Fastlane lane for TestFlight; document signing requirements in `platforms/ios/README.md`.

## Phase 4 — Desktop (Qt 6)

* `platforms/qt-desktop/` — CMake ≥ 3.21, Qt 6.5+ (Widgets or QML — pick Widgets for the smallest install footprint), C++17.
* `uztranslit.hpp/.cpp`: port using `QString`/`QChar` (iterate UTF-16 code units — all relevant letters are BMP), same function names as SPEC. `QTest` target `tst_fixtures` reads `spec/fixtures.json` via `QJsonDocument` (add the file with `qt_add_resources`).
* App: two editors side by side, direction controls, auto-detect label, swap, copy, open/save text files, drag-and-drop of files, batch folder conversion dialog (`.txt .md .csv .srt .html .json .xml` — convert only text nodes for `.html/.xml` using `QXmlStreamReader/Writer`), system tray with "Convert clipboard" actions and global shortcut (Qt has none built in — use QHotkey or document the limitation), Uzbek/English UI via Qt Linguist `.ts` files.
* CLI mode: `uztranslit --from auto --to new file.txt -o out.txt` (reuse Python CLI flags).
* Packaging: Windows (`windeployqt` + Inno Setup script), macOS (`macdeployqt` + dmg), Linux (AppImage via `linuxdeploy`). Matrix CI `desktop.yml`.

## Phase 5 — Microsoft Office

* `office-vba/UzTranslit.bas` is done and verified. Add:
  * `office-vba/ribbon/customUI14.xml` + instructions to build `UzTranslit.dotm` (Word), `UzTranslit.xlam` (Excel) and `UzTranslit.ppam` (PowerPoint) that import the module and show a **UzTranslit** ribbon tab (Office 2007+). For Office 97–2003 document the toolbar/`Tools ▸ Macro` path (already in `docs/OFFICE_INSTALL.md`).
  * Self-test: the module's `UzSelfTest` macro must show "N passed, 0 failed" — ask the user to run it once after import; put the number in the docs.
* **Office Add-in (Office.js)** for Office 2016+/Microsoft 365/Office on the web (platforms where VBA is unavailable: Office Online, iPad): `platforms/office-addin/` with `manifest.xml`, taskpane HTML using `core/js/uztranslit.js`, Word (`body.paragraphs` → `insertText` per range run via `getTextRanges` to keep formatting), Excel (`range.values`), PowerPoint (`slides.shapes.textFrame.textRange`). Host the taskpane on `https://latin.jaybi.uz/office/`. Add the sideload instructions.

## Phase 6 — LibreOffice polish

* Extension is working. Add: toolbar with icons (`Images.xcu`, 16/26 px PNG+SVG), localisation of menu titles (uz-UZ, ru-RU, en-US), an **Options page** (Tools ▸ Options ▸ UzTranslit) for apostrophe style and dictionary via `OptionsDialog.xcu`, and an **auto-load of the Basic library** so `=UZCONVERT()` works in Calc formulas without a prior menu click (document the current limitation: import `UzTranslitLO.bas` into My Macros ▸ Standard for formulas).
* Keep `tools/make_lo_basic.py --test` + `tools/lo_run_macro.py` as the regression gate and run them in CI.

## Phase 7 — dictionary & corpus work (ongoing)

* Build `tools/mine_dictionary.py`: from a parallel Cyrillic/Latin corpus (user-provided), find Latin words whose rule-based Cyrillic differs from the attested form and propose stems for SPEC §6 (Russian loans with ц, ъ, ь, йо). Every accepted stem gets a fixture.
* When the official 2026 *imlo qoidalari* are published, revisit SPEC §5.3/§5.4 (`sʼh`, `ng`, `ts`, the ўъ case) — spec first, fixtures second, ports third.

## Phase 8 — release

* `release.yml`: on tag `v*` build everything, attach `UzTranslit.bas`, `.dotm/.xlam/.ppam`, both `.oxt`, APK, desktop installers, and publish release notes listing the fixture counts per platform.
* Update `web/` downloads section to point at the release.

## Definition of done per phase

* All suites green (`tools/test_all.sh` + the platform's own fixture test).
* `README.md` platform table updated with install steps and the fixture count.
* One commit per phase; tag `v1.0.0` after Phase 8.
