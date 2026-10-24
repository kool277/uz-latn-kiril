# UzTranslit for LibreOffice (Writer, Calc, Impress, Draw)

Two ways to install — pick one.

## A. Extension (recommended): `libreoffice/uztranslit-libreoffice.oxt`

1. **Tools ▸ Extension Manager ▸ Add…** → choose `uztranslit-libreoffice.oxt` → restart LibreOffice.
   Command line: `unopkg add uztranslit-libreoffice.oxt` (add `--shared` for all users).
2. A **Tools ▸ UzTranslit** menu appears in Writer, Calc, Impress and Draw:
   *Avto → Yangi lotin (Ö Ğ Ş Ç)*, *Avto → Lotin 1995*, *Avto → Кирилл*, the six fixed directions, and *Self-test*.
3. The selection is converted; with nothing selected, the whole document (Writer: body, tables, text frames, footnotes, endnotes, comments, headers/footers; Calc: selected cells or the whole used area, cell comments; Impress/Draw: all shapes, groups, tables, notes).

What a run keeps:

* **Formatting.** Each paragraph is converted as one string, so a word whose letters are formatted differently (half bold) still converts as one word: casing (`Ш`+`АҲАР` → `SH`+`AHAR`), е/йе, digraphs and the dictionary see the whole word. The result is split back over the text portions, which keep all their attributes: character styles, language, hyperlinks, fonts, colours. Rich text in Calc cells keeps its runs; formulas are not touched.
* **Links and addresses.** URLs, e-mail addresses and @handles stay as they are.
* **One script decision.** *Avto* detects the script once for the whole selection or document.
* **One undo step.** <kbd>Ctrl</kbd>+<kbd>Z</kbd> takes the whole run back. Track changes is paused during the run (it would keep every old word next to its conversion) and switched back on afterwards.
* **Speed.** The screen is not redrawn during the run: a paragraph of 600 differently formatted runs (text pasted from a PDF) converts in a few seconds.

This edition is written in LibreOffice Basic (the same engine as the Office VBA module) and needs **no Python**, so it also works on Debian/Ubuntu builds without `libreoffice-script-provider-python`. CI checks it against the fixture corpus (210 conversions), 3,500 cases of the differential corpus and the paragraph splitter, and runs both editions end to end on Writer, Calc and Impress documents (`tools/lo_extension_test.py`). LibreOffice Basic is slow: about 1 ms per character, so a 100-page document takes a few minutes. The Python edition is several times faster.

`uztranslit-libreoffice-python.oxt` is the same extension using the Python core (`core/python/uztranslit.py`); it needs the Python script provider (`libreoffice-script-provider-python` on Debian/Ubuntu; bundled on Windows/macOS).

## B. Macro module: `libreoffice/UzTranslitLO.bas`

1. **Tools ▸ Macros ▸ Edit Macros** → in the Basic IDE select *My Macros ▸ Standard* → **Tools ▸ Import BASIC…** → `UzTranslitLO.bas`.
2. Run via **Tools ▸ Macros ▸ Run Macro ▸ My Macros ▸ Standard ▸ UzTranslitLO ▸ `UzLO_AutoToNew`** (etc.), or assign to a toolbar/shortcut (*Tools ▸ Customize*).
3. Calc formulas work with this method:
   `=UZCONVERT(A1;"lat";"new")`, `=UZCONVERT(A1;"auto";"cyr")`, `=UZDETECT(A1)`, `=UZLATTONEW(A1)`.
   (Formulas cannot see the library inside the extension until it is loaded; importing the module into *My Macros* avoids that.)

## Options

Set in the Basic IDE or your own macro: `UzOptAscii`, `UzOptKeepHardSignAfterO`, `UzOptNoTsFinal`, `UzOptNoDictionary`, `UzOptNoSkipUrls` (also convert URLs and e-mail addresses), `UzAddDictionary "stem", "стем"` — same as the Office module.

Unattended runs (scripts, tests): start soffice with `UZT_QUIET=1` in its environment and no message boxes are shown.

## Rebuilding

```
python3 tools/make_lo_basic.py          # office-vba/UzTranslit.bas + libreoffice/UzTranslitLO_ui.bas → libreoffice/UzTranslitLO.bas
python3 tools/build_oxt.py              # → both .oxt files
python3 tools/make_lo_basic.py --test && python3 tools/lo_run_macro.py Standard.UzTest.RunAll build/lo-test/result.txt   # headless fixture run
python3 tools/lo_run_macro.py UzOffice.UzCheck.Run build/lo-test/office.txt     # the whole MS Office module compiles
python3 tools/lo_extension_test.py              # installs both .oxt into throwaway profiles, converts Writer/Calc/Impress documents
```

All of these use throwaway profiles under `build/`, never your own LibreOffice profile.
