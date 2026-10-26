# UzTranslit Office installer (Windows)

`UzTranslit-<version>-Office-Setup.exe` puts the converter and its **UzTranslit** ribbon tab into Word and Excel
(2007 – 2024, Microsoft 365) on Windows in one click. It is attached to every release.

## Use

1. Close Word and Excel.
2. Run `UzTranslit-…-Office-Setup.exe` (unsigned: *More info ▸ Run anyway* in SmartScreen), tick Word and/or
   Excel, press **Oʻrnatish / Установить / Install**.
3. Open Word or Excel: the **UzTranslit** tab has *Yangi lotin*, *Lotin 1995*, *Кирилл*, the six fixed directions
   and *Oʻz-oʻzini tekshirish* (`UzSelfTest`, which must say *29 passed, 0 failed*).

**Olib tashlash / Удалить / Uninstall** in the same window removes both files. Without the window (for
administrators, per user):

```
UzTranslit-1.1.0-Office-Setup.exe --install --quiet        (--word or --excel for one of them)
UzTranslit-1.1.0-Office-Setup.exe --uninstall --quiet
```

The exit code is 0 on success; the log is `%LOCALAPPDATA%\UzTranslit\office-installer.log`.

## What it does

For each application found (`HKCR\Word.Application\CurVer`, `Excel.Application\CurVer`):

1. Sets `HKCU\Software\Microsoft\Office\<version>\<Word|Excel>\Security\AccessVBOM` = 1 ("Trust access to the VBA
   project object model") for the moment, and afterwards puts the old value back (or removes it). If a group policy
   forbids it, the installer stops with that message and changes nothing.
2. Starts a **separate, hidden** instance of Word / Excel through COM (`DispatchEx`; open windows are left alone,
   macros are disabled in it), imports `office-vba/UzTranslit.bas` and `UzTranslitRibbon.bas` into a new
   document / workbook and saves it as `UzTranslit.dotm` (Word macro-enabled template) / `UzTranslit.xlam` (Excel
   add-in), then quits it.
3. Adds the ribbon with `tools/add_ribbon.py` (`office-vba/ribbon/customUI.xml` for Office 2007,
   `customUI14.xml` for 2010 and later, and the icons) and checks that the file has its VBA project and ribbon.
4. Copies it into the folder the application reports as its startup folder — by default
   `%APPDATA%\Microsoft\Word\STARTUP` and `%APPDATA%\Microsoft\Excel\XLSTART`. Office loads those files with every
   document, and both folders are trusted locations, so the macros run without a security warning. When the old
   file is still open (Word or Excel running), the installer asks to close it and retries.

**`Normal.dotm` and `PERSONAL.XLSB` are never changed**: they hold the user's own macros, styles and settings, and
a separate global template / add-in can be removed again without touching them.

Not covered: PowerPoint (its add-ins must be registered from inside PowerPoint: see `docs/OFFICE_INSTALL.md`),
Office 97 – 2003 (no ribbon and no `.dotm`), Office for Mac, and organisations where trusted locations are turned off
by policy (the tab then appears but the macros are blocked: sign the files or import the modules by hand).

## Build

On Windows with Python 3.9 or later, from the repository root:

```
py -m pip install -r platforms/office-installer/requirements.txt
py platforms/office-installer/build.py
```

→ `build\office-installer\dist\UzTranslit-Office-Setup.exe`. `build.py` is
`pyinstaller --noconsole --onefile installer.py` plus the bundled modules and ribbon (`--add-data`),
`tools/add_ribbon.py` (`--paths`) and an icon. Without building: `py platforms/office-installer/installer.py`
(needs `pywin32`).

## Tests

```
python3 platforms/office-installer/test_installer.py
```

Office is not available in CI, so fake Word and Excel COM objects record the calls (modules imported in order, the
file format, documents closed, the instance quit even after an error) and save a real Office package; the registry is
a dictionary. Everything else runs for real: AccessVBOM set and restored, the policy and "not trusted" errors, ribbon
injection, the startup folders, the retry on a locked file, the state file and uninstall. On Windows,
`.github/workflows/office-installer.yml` also builds the exe and starts it with `--check` to see that it carries
every file. The installation into a real Word / Excel is not tested in CI.
