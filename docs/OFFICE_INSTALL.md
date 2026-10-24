# UzTranslit for Microsoft Office (Word, Excel, PowerPoint 97 → 2026)

One file: `office-vba/UzTranslit.bas`. Pure VBA, no references, no Unicode in the source (everything is built with `ChrW`), so it imports cleanly into any VBA editor code page and runs on Office 97, 2000, XP, 2003, 2007, 2010, 2013, 2016, 2019, 2021, 2024, Microsoft 365 (Windows and Mac). It cannot run in Office on the web or on iPad — use https://latin.jaybi.uz or the Office.js add-in there.

## Install (any version)

1. Open Word / Excel / PowerPoint. Press **Alt+F11** (Visual Basic Editor).
2. **File ▸ Import File…** → choose `UzTranslit.bas`. A module named *UzTranslit* appears under *Modules*.
   * Word: import into **Normal** (so it is available in every document) — select "Normal" in the project tree first.
   * Excel: import into **PERSONAL.XLSB** (create it once via *Record Macro ▸ Store in: Personal Macro Workbook*).
   * PowerPoint: import into a presentation or save as a `.ppam` add-in (File ▸ Save As ▸ PowerPoint Add-in).
3. Close the editor. Press **Alt+F8**, run **`UzSelfTest`** — it must say *passed, 0 failed*.
4. Macro security: *File ▸ Options ▸ Trust Center ▸ Macro Settings* → "Disable all macros with notification" is enough; enable macros when prompted. For Office 97–2003: *Tools ▸ Macro ▸ Security ▸ Medium*.

## Use

Press **Alt+F8** and run one of:

| Macro | Does |
|---|---|
| `UzTranslit_AutoToNew` | detect the script of each fragment → **Yangi lotin** (Ö Ğ Ş Ç) |
| `UzTranslit_AutoToLat` | → Lotin 1995 |
| `UzTranslit_AutoToCyr` | → Кирилл |
| `UzTranslit_LatToNew`, `UzTranslit_NewToLat`, `UzTranslit_CyrToLat`, `UzTranslit_CyrToNew`, `UzTranslit_LatToCyr`, `UzTranslit_NewToCyr` | fixed directions |

* **Word**: converts the selection, or — with nothing selected — the whole document including tables, headers/footers, footnotes, text boxes. Paragraphs with uniform formatting are converted in one step; mixed paragraphs are converted run by run so bold/italic/colour are kept. Fields and hyperlinks are skipped. Track Changes is paused during conversion.
* **Excel**: converts the selected cells (text constants only; formulas and numbers are untouched). With a single cell selected you are asked whether to convert the whole sheet. Formulas: `=UzConvert(A1,"lat","new")`, `=UzConvert(A1,"auto","cyr")`, `=UzDetect(A1)`.
* **PowerPoint**: every slide, shape, group, table cell and notes page, run by run (formatting kept).

Put the macros on the Quick Access Toolbar: *File ▸ Options ▸ Quick Access Toolbar ▸ Choose commands from: Macros*. Office 97–2003: *Tools ▸ Customize ▸ Commands ▸ Macros* and drag to a toolbar.

## Options (set from the Immediate window, Ctrl+G, or in your own macro)

```vba
UzOptAscii = True                 ' write ' instead of ʻ / ʼ
UzOptKeepHardSignAfterO = True    ' мўъжиза → moʻʼjiza instead of moʻjiza
UzOptNoTsFinal = True             ' never turn word-final "ts" into ц
UzOptNoDictionary = True          ' skip the loanword dictionary (obyekt → объект …)
UzAddDictionary "fizika", ChrW(&H444) & ChrW(&H438) & ChrW(&H437) & ChrW(&H438) & ChrW(&H43A) & ChrW(&H430)
```

## Known limits

* The VBA editor shows non-ASCII poorly on non-Cyrillic Windows — that is why the source uses `ChrW`; the converted documents are fine.
* Word: a word whose letters have different formatting (half bold) is converted run by run; a digraph split across the boundary (`S`|`h`) would be treated as two letters. Rare in practice.
* Excel rich-text cells (partly bold cell text) lose the partial formatting; the text is converted correctly.
* Outlook: use the Word editor (Alt+F11 in an open message) or the web app.
