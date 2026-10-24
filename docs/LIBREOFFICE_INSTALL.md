# UzTranslit for LibreOffice (Writer, Calc, Impress, Draw)

Two ways to install — pick one.

## A. Extension (recommended): `libreoffice/uztranslit-libreoffice.oxt`

1. **Tools ▸ Extension Manager ▸ Add…** → choose `uztranslit-libreoffice.oxt` → restart LibreOffice.
   Command line: `unopkg add uztranslit-libreoffice.oxt` (add `--shared` for all users).
2. A **Tools ▸ UzTranslit** menu appears in Writer, Calc, Impress and Draw:
   *Avto → Yangi lotin (Ö Ğ Ş Ç)*, *Avto → Lotin 1995*, *Avto → Кирилл*, the six fixed directions, and *Self-test*.
3. The selection is converted; with nothing selected, the whole document (Writer: body, tables, text frames, footnotes, headers/footers; Calc: selected cells or the whole used area; Impress/Draw: all shapes, groups, tables, notes). Character formatting is preserved (conversion is done per text portion and attributes are restored).

This edition is written in LibreOffice Basic (the same engine as the Office VBA module, verified against the 212-case fixture corpus) and needs **no Python** — it also works on Debian/Ubuntu builds without `libreoffice-script-provider-python`.

`uztranslit-libreoffice-python.oxt` is the same extension using the Python core (`core/python/uztranslit.py`); it needs the Python script provider (`libreoffice-script-provider-python` on Debian/Ubuntu; bundled on Windows/macOS).

## B. Macro module: `libreoffice/UzTranslitLO.bas`

1. **Tools ▸ Macros ▸ Edit Macros** → in the Basic IDE select *My Macros ▸ Standard* → **Tools ▸ Import BASIC…** → `UzTranslitLO.bas`.
2. Run via **Tools ▸ Macros ▸ Run Macro ▸ My Macros ▸ Standard ▸ UzTranslitLO ▸ `UzLO_AutoToNew`** (etc.), or assign to a toolbar/shortcut (*Tools ▸ Customize*).
3. Calc formulas work with this method:
   `=UZCONVERT(A1;"lat";"new")`, `=UZCONVERT(A1;"auto";"cyr")`, `=UZDETECT(A1)`, `=UZLATTONEW(A1)`.
   (Formulas cannot see the library inside the extension until it is loaded; importing the module into *My Macros* avoids that.)

## Options

Set in the Basic IDE or your own macro: `UzOptAscii`, `UzOptKeepHardSignAfterO`, `UzOptNoTsFinal`, `UzOptNoDictionary`, `UzAddDictionary "stem", "стем"` — same as the Office module.

## Rebuilding

```
python3 tools/make_lo_basic.py          # office-vba/UzTranslit.bas + libreoffice/UzTranslitLO_ui.bas → libreoffice/UzTranslitLO.bas
python3 tools/build_oxt.py              # → both .oxt files
python3 tools/make_lo_basic.py --test && python3 tools/lo_run_macro.py Standard.UzTest.RunAll build/lo-test/result.txt   # headless fixture run
```
