# UzTranslit for the desktop (Qt 6, C++17)

Windows, macOS and Linux app that converts Uzbek text between Cyrillic (`cyr`), Latin 1995 (`lat`) and Latin 2026
(`new`: Ö Ğ Ş Ç, law OʻRQ-1184), plus a command-line converter in the same binary.

* `core/uztranslit.hpp/.cpp` (library `uztranslit_core`, Qt Core only): a faithful port of `spec/SPEC.md` §5 with
  the reference helper names (`isCyr`, `isLat`, `isApos`, `nextLetterIsUpper`, `caseOut`, `cyrToLatin`,
  `latinToCyrScan`, `convertWordWithDict`, `latToNew`, `newToLat`, `detect`), the §6 dictionary and the spec default
  options. Text is walked in UTF-16 code units (`QChar`), like JavaScript. Case mapping uses only the spec's tables
  (never `QChar::toLower`/locale rules), and the URL / e-mail / @handle protection of §5.6 is an index scanner that
  reproduces the reference RegExp `/(https?:\/\/|www\.)\S+|\S+@\S+\.\S+|@\w+/g` with JavaScript's `\s` and ASCII `\w`
  (QRegularExpression's classes differ).
* `src/`: text files (UTF-8 with or without BOM, UTF-16 with BOM; the encoding and BOM are written back unchanged,
  anything else is refused rather than decoded lossily), format-aware document conversion, batch jobs, the CLI and
  the Widgets interface.

## Build and test

Requirements: CMake ≥ 3.21, Qt ≥ 6.5 (Core, Gui, Widgets, LinguistTools, Test) — CI uses Qt 6.8 LTS —, a C++17
compiler (GCC, Clang, MSVC 2022), Node.js to generate the differential corpus.

```sh
node tools/make_differential.mjs                     # at the repository root: build/differential.json
cd platforms/qt-desktop
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build -j4
ctest --test-dir build --output-on-failure
```

Without Qt on the machine, build and test in Docker (Debian trixie ships Qt 6.8); run as your user so that the
build tree is not owned by root:

```sh
docker build -t uztranslit-qt platforms/qt-desktop/docker
docker run --rm --user "$(id -u):$(id -g)" -v "$PWD":/repo -w /repo/platforms/qt-desktop uztranslit-qt \
  sh -c 'cmake -S . -B build -G Ninja && cmake --build build -j4 && ctest --test-dir build --output-on-failure'
```

| test | what it checks |
|---|---|
| `tst_fixtures` | `spec/fixtures.json` (cases, roundtrips, detect, optional): **212 passed, 0 failed**. CMake copies the file into the build tree (`configure_file`) and compiles it into a Qt resource; no case is written in C++. |
| `tst_differential` | `build/differential.json` from the reference `core/js/uztranslit.js`: **20,000 conversions + 2,000 detections** (every direction, random options, URL fragments, JS whitespace look-alikes). Copied the same way when the file exists at configure time, otherwise skipped with a message (configure again after generating it). |
| `tst_documents` | UTF-8/UTF-16/BOM round trips, Markdown, SubRip, JSON, HTML, XHTML and XML conversion, auto-detection ignoring markup, batch folders (hidden files, output inside the source, never overwriting a source). |
| `tst_cli` | the real binary in CLI mode with a non-existent Qt platform plugin and no `DISPLAY`: stdin/stdout, files, `-o`, `--ascii`, BOM/UTF-16 kept, argparse-style errors and exit codes, and all 192 fixture cases through the command line. |
| `tst_gui` | offscreen GUI: live conversion while typing, buttons, no-break spaces kept, swap (undoable), copy, clipboard actions, open/save keeping BOM and CRLF, HTML opened in the editor, drag and drop of files and folders, the three interface languages, settings persistence, the batch dialog converting a folder. `UZT_SCREENSHOT_DIR=dir` also saves screenshots. |
| `tst_translations` | every message of `translations/*.ts` is translated, placeholders and `&` accelerators match the source, no invisible characters. |
| `gui_smoke` | starts the real app on the offscreen platform with a file argument, converts it and quits (testing aids in `src/main.cpp`: `UZTRANSLIT_QUIT_AFTER_MS`, `UZTRANSLIT_SMOKE_RESULT`, `UZTRANSLIT_SETTINGS_DIR`). |

## Command line

The same binary converts on the command line when it is given converter flags; it then runs on a
`QCoreApplication` and needs no display. The flags mirror `core/python/uztranslit.py`:

```
uztranslit [-h] [--from {auto,cyr,lat,new}] --to {cyr,lat,new} [--ascii] [-o OUTPUT] [file]

uztranslit --from auto --to new file.txt -o out.txt
uztranslit --to cyr < in.txt > out.txt          # stdin → stdout (also with "-" as the file)
uztranslit --from cyr --to lat --ascii file.txt  # ' instead of ʻ and ʼ
```

`--from` defaults to `auto`; long options may be abbreviated (`--fr`, `--asc`) and written as `--to=new`, like
argparse. Exit codes: 0 success, 1 input/output error (missing file, not UTF-8/UTF-16), 2 usage error. The output
keeps the input's encoding, byte-order mark and line ends. A single file argument without flags opens the window.

* Windows: `uztranslit.exe` is a GUI program; it attaches to the console it was started from. `cmd.exe` does not wait
  for GUI programs, so use `-o` or redirect the output (`uztranslit --to new a.txt > b.txt`), or
  `start /wait uztranslit …`. Add the folder to `PATH` with the installer option.
* macOS: `/Applications/UzTranslit.app/Contents/MacOS/UzTranslit --to new file.txt`.
* Linux: `./UzTranslit-1.0.0-x86_64.AppImage --to new file.txt`. The binary links Qt GUI, so a headless server
  needs the usual desktop libraries that AppImages leave to the system (`libegl1`, `libgl1`, `libfontconfig1`,
  `libfreetype6`, `libharfbuzz0b`, `libglib2.0-0`, `libx11-6`, …) even for the CLI, but no display.

## The app

* Two editors side by side with live conversion; source **Avto / Кирилл / Lotin 1995 / Yangi lotin**, target
  Кирилл / Lotin 1995 / Yangi lotin; the detected script is shown for Avto; swap (continues with the result, undoable
  with Ctrl+Z), copy, paste, clear, character and word counts.
* Open/save text files (UTF-8 or UTF-16; the result is saved with the input's encoding, BOM and line ends; while the
  input is unedited, the exact file text is converted, not the editor's normalised copy). Files opened in the editor
  are converted by format: an HTML file keeps its tags.
* Drag and drop: a file opens in the editor, a folder or several files open the batch dialog.
* **Batch conversion** (File ▸ Convert a folder…): `.txt .md .csv .srt .html .json .xml` (and `.htm`), optionally
  with subfolders, into a separate output folder (the originals are never changed; a converted file is never written
  over its source). Per format: plain text and CSV whole; Markdown without front matter, code, link targets, autolinks
  and HTML tags; SubRip cue text only (no numbers, timings, `<i>`/`{\an8}` tags); JSON string values only (never keys;
  escapes decoded and written back in the same style); HTML text nodes only via a tag-preserving rewrite (no
  `script/style/code/kbd/samp/var/svg/math/template`, no `translate="no"`/`notranslate`, entities kept, attributes
  untouched); XML — and HTML files that are well-formed XHTML — through `QXmlStreamReader` → `QXmlStreamWriter`
  (character data outside script/style/CDATA; the XML declaration, prolog, DTD and script/style content are copied as
  written, `<a></a>` is not collapsed to `<a/>`, CRLF files keep CRLF). An XML file that is not well-formed is
  converted with the HTML-style rewrite and the log says so. For Avto the script is detected from the text, not the
  markup.
* System tray: "Convert clipboard to kirill / lotin 1995 / yangi lotin" (auto-detected source), show window, quit;
  the same actions are in Edit ▸ Convert the clipboard. Settings ▸ "Keep running in the system tray when the window is
  closed" keeps the tray icon alive.
* Interface languages: Oʻzbekcha (Latin 1995, default), Русский (default on a Russian system), English (the source
  language of the strings). Qt Linguist files `translations/uztranslit_{uz,ru}.ts` are compiled by
  `qt_add_translations` into the binary; they also cover the Qt strings the app shows (editor context menus, message
  box buttons, scroll bar menus). Run `cmake --build build --target update_translations` after changing strings.
* Settings (QSettings): source and default target, apostrophe style, dictionary, `dropHardSignAfterO`, `tsFinal`,
  URL protection, tray behaviour, language, window geometry.

## Packaging

| platform | script | result |
|---|---|---|
| Linux | `packaging/linux/build-appimage.sh [build-dir]` — `cmake --install` into an AppDir, then linuxdeploy + linuxdeploy-plugin-qt (pinned releases, SHA-256 checked, no FUSE needed) | `UzTranslit-<version>-x86_64.AppImage` |
| Windows | `packaging/windows/deploy.ps1` (windeployqt + app-local MSVC runtime, from a VS developer shell) then Inno Setup ≥ 6.3: `iscc /DAppVersion=… /DDeployDir=… /DOutputDir=… packaging/installer/uztranslit.iss` | `UzTranslit-<version>-Windows-x64-setup.exe` (per-user by default, optional PATH entry and desktop icon) |
| macOS | `packaging/macos/build-dmg.sh [build-dir]` — macdeployqt, ad-hoc `codesign`, `hdiutil` (CI builds a universal arm64 + x86_64 app, macOS 12+) | `UzTranslit-<version>-macOS.dmg` |

`.github/workflows/desktop.yml` builds, tests and packages on ubuntu-24.04, windows-latest and macos-15 with Qt 6.8
(jurplel/install-qt-action) and uploads the three packages as artifacts. Icons: `packaging/make-icons.py` (Pillow)
draws them into `resources/icons/` (PNG), `packaging/windows/uztranslit.ico` and `packaging/macos/uztranslit.icns`.

## Known limitations

* **No global hotkey.** Qt has no API for system-wide shortcuts, and this project adds no third-party dependency
  (QHotkey or platform code). Use the tray menu, or bind a desktop/OS shortcut to a command such as
  `xclip -o -sel clip | uztranslit --to new | xclip -sel clip` (Linux) or a macOS Shortcuts/Automator action that
  runs the CLI.
* Packages are not code-signed: Windows SmartScreen and macOS Gatekeeper warn on first start (macOS: right-click ▸
  Open). The dmg is signed ad hoc only and not notarized.
* The AppImage needs a glibc at least as new as the build machine's (ubuntu-24.04 in CI: glibc 2.39) and the system's
  OpenGL/EGL, fontconfig, FreeType and HarfBuzz libraries, which AppImages leave to the system. It uses X11 (XWayland on Wayland desktops).
* Documents: a word split by inline markup (`O<b>ʻ</b>zbek`, `<b>Ш</b>АҲАР`) is converted piece by piece, because
  each text node is converted on its own; HTML/XML attributes (`title`, `alt`) are not converted; CDATA sections are
  left as they are; in XML the stream writer re-serialises markup (attribute quotes become `"`, character references
  become characters). Files must be UTF-8 or UTF-16 (legacy code pages such as Windows-1251 are refused, not guessed).
* The installer's own wizard is English or Russian: Inno Setup ships no Uzbek messages file.
