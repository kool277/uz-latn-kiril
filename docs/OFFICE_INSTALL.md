# UzTranslit for Microsoft Office (Word, Excel, PowerPoint 97 → 2026)

One file: `office-vba/UzTranslit.bas`. Pure VBA, no references, no Unicode in the source (everything is built with `ChrW`), so it imports cleanly into any VBA editor code page and runs on Office 97, 2000, XP, 2003, 2007, 2010, 2013, 2016, 2019, 2021, 2024, Microsoft 365 (Windows and Mac). It cannot run in Office on the web or on iPad — use https://latin.jaybi.uz or the Office.js add-in there.

## Install (any version)

1. Open Word / Excel / PowerPoint. Press **Alt+F11** (Visual Basic Editor).
2. **File ▸ Import File…** → choose `UzTranslit.bas`. A module named *UzTranslit* appears under *Modules*.
   The file has Windows line ends (CRLF), which the VBA editor needs; download it as a file (the web app's download button, a release, or *Raw ▸ Save as* on GitHub) rather than copying it through an editor that might change them. If you see `Attribute VB_Name = "UzTranslit"` as a red line in the code, the line ends were changed: delete the module and import the downloaded file again.
   * Word: import into **Normal** (so it is available in every document) — select "Normal" in the project tree first.
   * Excel: import into **PERSONAL.XLSB** (create it once via *Record Macro ▸ Store in: Personal Macro Workbook*).
   * PowerPoint: import into a presentation or save as a `.ppam` add-in (File ▸ Save As ▸ PowerPoint Add-in).
3. Close the editor. Press **Alt+F8**, run **`UzSelfTest`** — it must say *29 passed, 0 failed* (CI runs the same 29 checks in LibreOffice's VBA mode).
4. Macro security: *File ▸ Options ▸ Trust Center ▸ Macro Settings* → "Disable all macros with notification" is enough; enable macros when prompted. For Office 97–2003: *Tools ▸ Macro ▸ Security ▸ Medium*.

## Use

Press **Alt+F8** and run one of:

| Macro | Does |
|---|---|
| `UzTranslit_AutoToNew` | detect the script (once, for the whole selection or document) → **Yangi lotin** (Ö Ğ Ş Ç) |
| `UzTranslit_AutoToLat` | → Lotin 1995 |
| `UzTranslit_AutoToCyr` | → Кирилл |
| `UzTranslit_LatToNew`, `UzTranslit_NewToLat`, `UzTranslit_CyrToLat`, `UzTranslit_CyrToNew`, `UzTranslit_LatToCyr`, `UzTranslit_NewToCyr` | fixed directions |

* **Word**: converts the selection, or — with nothing selected — the whole document including tables, headers/footers, footnotes, text boxes. Each paragraph is converted as one string, so a word whose letters are formatted differently (half bold) still converts as one word, and the result is split back over the runs, which keep their formatting. Fields, pictures, content controls and footnote/comment marks are never rewritten; hyperlinks keep their address and their text is converted; bookmarks (which a table of contents and cross-references point to) are kept. Track Changes is paused during conversion; in Word 2010 and later the whole run is one undo step. Update fields afterwards (<kbd>Ctrl</kbd>+<kbd>A</kbd>, <kbd>F9</kbd>) so a table of contents shows the converted headings.
* **Excel**: converts the selected cells (text constants only; formulas and numbers are untouched, also when a single formula cell is selected). With a single cell selected you are asked whether to convert the whole sheet. Rich text in a cell (partly bold) keeps its runs: font, size, bold, italic, underline, colour, strikethrough, super/subscript (a theme colour becomes the same fixed colour). A cell stays text even if its converted value looks like a number, date or formula. Excel cannot undo a macro: save first. Formulas: `=UzConvert(A1,"lat","new")`, `=UzConvert(A1,"auto","cyr")`, `=UzDetect(A1)`.
* **PowerPoint**: every slide, shape, group, table cell and notes page; each paragraph is converted as one string and split back over its runs (formatting kept).
* URLs, e-mail addresses and @handles are left as they are everywhere (`UzOptNoSkipUrls = True` converts them too).

## UzTranslit ribbon tab (Office 2007 and later)

A **UzTranslit** tab with *Yangi lotin*, *Lotin 1995*, *Кирилл*, a menu of the six fixed directions and the self-test. Office cannot add a tab to a file by itself, and a VBA project can only be written by Office, so it takes one round trip:

1. Import **both** `UzTranslit.bas` and `UzTranslitRibbon.bas` (the button handler) into a new, empty file, then **File ▸ Save As**:
   * Word: *Word Macro-Enabled Template* → `UzTranslit.dotm`
   * Excel: *Excel Add-in* → `UzTranslit.xlam`
   * PowerPoint: save as `UzTranslit.pptm` first, then *PowerPoint Add-in* → `UzTranslit.ppam`
2. Close Office and add the tab (Python 3, no packages needed):
   ```
   python3 tools/add_ribbon.py UzTranslit.dotm
   ```
   It adds `office-vba/ribbon/customUI.xml` (Office 2007), `customUI14.xml` (2010 and later) and the icons, and changes nothing else in the file. Running it again replaces the tab.
3. Load it:
   * Word: copy `UzTranslit.dotm` to the STARTUP folder (`%APPDATA%\Microsoft\Word\STARTUP`; on a Mac, Word ▸ Preferences ▸ File Locations ▸ Startup).
   * Excel: *File ▸ Options ▸ Add-ins ▸ Manage: Excel Add-ins ▸ Go… ▸ Browse* → `UzTranslit.xlam`.
   * PowerPoint: *File ▸ Options ▸ Add-ins ▸ Manage: PowerPoint Add-ins ▸ Go… ▸ Add New* → `UzTranslit.ppam`.

If the tab does not appear, turn on *File ▸ Options ▸ Advanced ▸ General ▸ Show add-in user interface errors* and reopen: Office then names the problem. `tools/test_add_ribbon.py` checks the injection on Word, Excel and PowerPoint files and that every button has a handler; the tab itself is only visible in Office.

Office 97–2003 have no ribbon: use the toolbar below.

Put the macros on the Quick Access Toolbar: *File ▸ Options ▸ Quick Access Toolbar ▸ Choose commands from: Macros*. Office 97–2003: *Tools ▸ Customize ▸ Commands ▸ Macros* and drag to a toolbar.

## Options (set from the Immediate window, Ctrl+G, or in your own macro)

```vba
UzOptAscii = True                 ' write ' instead of ʻ / ʼ
UzOptKeepHardSignAfterO = True    ' мўъжиза → moʻʼjiza instead of moʻjiza
UzOptNoTsFinal = True             ' never turn word-final "ts" into ц
UzOptNoDictionary = True          ' skip the loanword dictionary (obyekt → объект …)
UzOptNoSkipUrls = True            ' also convert URLs, e-mail addresses and @handles
UzAddDictionary "fizika", ChrW(&H444) & ChrW(&H438) & ChrW(&H437) & ChrW(&H438) & ChrW(&H43A) & ChrW(&H430)
```

## Known limits

* The VBA editor shows non-ASCII poorly on non-Cyrillic Windows — that is why the source uses `ChrW`; the converted documents are fine.
* How it is tested: the engine (`UzConvert`, `UzDetect`, `UzSplitConvert`) runs in CI in LibreOffice Basic's VBA mode against the fixture corpus, the differential corpus and LibreOffice documents. The Word/Excel/PowerPoint macros need Office itself, which CI does not have: CI compiles them in LibreOffice's VBA mode and `tools/vba_lint.py` checks them for undeclared names (a single one would stop every macro in the module from compiling in Office). Report a problem with a sample document if a macro misbehaves.
* Where formatting changes inside a word right at a letter that a rule looks across (a digraph cut by formatting, `S`|`h`), a letter may move to the neighbouring run; the text itself is always exactly the conversion of the whole paragraph.
* Outlook: use the Word editor (Alt+F11 in an open message) or the web app.
