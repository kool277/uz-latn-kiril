# UzTranslit — Oʻzbek alifbo konvertori

Converts Uzbek text between **Cyrillic (1940)**, **Latin 1995** (Oʻ Gʻ Sh Ch) and the **Latin alphabet of 2026**
adopted by law **OʻRQ-1184 (21 October 2026)**: **Oʻ → Ö, Gʻ → Ğ, Sh → Ş, Ch → Ç**, `ng` dropped as a letter, tutuq belgisi ʼ kept — 28 letters + ʼ, in force six months after publication.

All six directions, with the rules that matter: е/э, ц → s/ts, ъ/ь, йў vs ё, `sʼh` ↔ `sh`, casing of digraphs (ШАҲАР → SHAHAR / Şahar), a loanword dictionary (obyekt → объект, kompyuter → компьютер, sirk → цирк …), auto-detection, URL/e-mail protection.

## What is in the kit

| Part | Path | Status |
|---|---|---|
| Specification + 212-case conformance corpus | `spec/` | source of truth |
| JavaScript core (browser/Node, UMD) | `core/js/uztranslit.js` | 212/212 ✔ |
| Python core + CLI | `core/python/uztranslit.py` | 212/212 ✔ |
| Web app for **https://latin.jaybi.uz** (GitHub Pages, PWA, offline) | `web/` | ready to push |
| MS Office macro module (Word/Excel/PowerPoint 97 → 2026, VBA 5–7) | `office-vba/UzTranslit.bas` | engine executed in LibreOffice Basic VBA mode: 210/210 ✔ |
| LibreOffice extension (menu Tools ▸ UzTranslit) | `libreoffice/uztranslit-libreoffice.oxt` | installed + e2e-tested in Writer/Calc/Impress ✔ |
| LibreOffice Basic module / Python edition | `libreoffice/UzTranslitLO.bas`, `uztranslit-libreoffice-python.oxt` | ✔ / needs Python provider |
| Claude Code master prompt (Android, iOS, Qt 6, Office.js add-in, CI, releases) | `CLAUDE_CODE_PROMPT.md` + `CLAUDE.md` | run it |

## Quick start

```bash
node core/js/test.js                              # 212 passed
python3 core/python/test_uztranslit.py            # 212 passed
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

## Deploy the web app to latin.jaybi.uz

1. Push the contents of `web/` to the branch/folder your GitHub Pages site is built from (the `CNAME` file already contains `latin.jaybi.uz`).
2. DNS: `latin` → CNAME → `<your-user>.github.io`. In the repo's *Settings ▸ Pages* set the custom domain and tick *Enforce HTTPS* once the certificate is issued.
3. Everything runs client-side; the service worker makes it work offline.

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

* Cyrillic е → `ye` at word start / after a vowel / after ъ ь, else `e`; ц → `ts` after a vowel, else `s`; ъ → ʼ (dropped before е ё ю я and after ў); ь dropped.
* 1995 Latin `sʼh` (Isʼhoq) becomes plain `sh` in 2026 Latin (Ishoq) because Ş makes it unambiguous; the reverse inserts ʼ again.
* `yoʻl` → йўл, `tayyor` → тайёр, `oʻtsa` stays ўтса while `militsiya` → милиция, `abzats` → абзац.
* Casing: ШАҲАР → SHAHAR, Шаҳар → Shahar, Ş alone → Sh.
* The 2026 *imlo qoidalari* are not published yet; the few open points (ўъ, `ng`) are options, documented in SPEC §7.

MIT License.
