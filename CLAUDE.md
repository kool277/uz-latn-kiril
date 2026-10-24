# CLAUDE.md — standing rules for this repository

UzTranslit converts Uzbek text between Cyrillic (`cyr`), Latin 1995 (`lat`) and Latin 2026 (`new`: Ö Ğ Ş Ç per law OʻRQ-1184, 21 Oct 2026).

## Source of truth
- `spec/SPEC.md` defines the algorithm; `spec/fixtures.json` defines correctness (212 checks). Both are versioned together.
- A conversion rule is changed **only** by editing the spec and fixtures first, then every port. Never patch one port.
- Ports: `core/js` (reference), `core/python`, `office-vba` (VBA 5–7, also feeds `libreoffice/` through `tools/make_lo_basic.py`). Planned under `platforms/` (not started yet, see `CLAUDE_CODE_PROMPT.md`): android (Kotlin), ios (Swift), qt-desktop (C++), office-addin (Office.js).

## How to test
```
tools/test_all.sh                      # JS + Python (+ LibreOffice Basic when soffice is installed)
node core/js/test.js
python3 core/python/test_uztranslit.py
python3 tools/make_lo_basic.py --test && python3 tools/lo_run_macro.py Standard.UzTest.RunAll build/lo-test/result.txt
python3 tools/build_oxt.py             # rebuilds both .oxt files
```
A change is not done until every suite prints `0 failed`.
The LibreOffice suite runs soffice with a throwaway profile in `build/lo-test/profile`; never point it at the real
`~/.config/libreoffice` profile — installing the test library there replaces the user's My Macros ▸ Standard.

## Porting rules
- Keep SPEC §5 helper names and the index-based scanner in every language; no regex-only implementations.
- All relevant characters are in the BMP, so UTF-16 code-unit iteration (JS, Qt, Swift UTF-16 view, Kotlin) is fine.
- Empty-string/undefined guards: `"".indexOf("")` is 0 in JS — every helper must treat "no character" explicitly.
- Basic is case-insensitive: never declare `n` and `N` in one scope. Single-line `If … Then Sub a, b Else Sub c, d` is invalid in LibreOffice Basic — use block `If`.
- Non-ASCII in `office-vba/UzTranslit.bas` only via `ChrW`/`U("hex hex …")`; the module must stay pure ASCII.
- Rich-text hosts: convert runs/portions (Word runs, LibreOffice text portions, PowerPoint `Runs`), restore character attributes after replacing a portion (`UzLO_ReplacePortion` / `_replace_portion`).
- Default options: okina U+02BB, tutuq U+02BC, dropHardSignAfterO, tsFinal, dictionary, skipUrls (where tokenisation is possible).

## Conventions
- UI language: Uzbek (Latin), English fallback. Labels: Кирилл / Lotin 1995 / Yangi lotin.
- Conventional commits; one phase per commit; update `README.md` platform table with every platform change.
- Web: `web/` is deployed to GitHub Pages as https://latin.jaybi.uz — keep `web/CNAME`, keep `web/uztranslit.js` identical to `core/js/uztranslit.js`.
