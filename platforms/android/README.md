# UzTranslit for Android

Converts Uzbek text between **Кирилл**, **Lotin 1995** and **Yangi lotin** (Latin 2026, OʻRQ-1184: Ö Ğ Ş Ç) on the
phone, offline: no permissions, nothing is sent anywhere. Interface in Uzbek (Latin 1995), Russian and English.

| Module | What it is |
|---|---|
| `core` | The engine: a pure Kotlin/JVM port of [`spec/SPEC.md`](../../spec/SPEC.md) §5–§6 (`UzTranslit.kt`, `UzDictionary.kt`), no Android dependencies |
| `app` | The Android app (Jetpack Compose, Material 3, dynamic colour, dark theme), minSdk 24, target/compile SDK 37 |

## Build, test, install

Needs JDK 17 or later (21 is what CI uses) and the Android SDK (platform `android-37.0`, build tools 36.0.0; Gradle downloads missing SDK parts
when the licences are accepted). Point Gradle at the SDK with `ANDROID_HOME` or a `local.properties` file
(`sdk.dir=/path/to/android-sdk`, not committed). Node.js is only needed for the differential corpus.

```bash
node tools/make_differential.mjs        # in the repository root: writes build/differential.json (optional)
cd platforms/android
./gradlew test assembleDebug             # every unit test + app/build/outputs/apk/debug/app-debug.apk
./gradlew :core:test                     # just the engine: fixtures, differential test, dictionary, API
./gradlew lint                           # Android lint (clean)
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

CI: [`.github/workflows/android.yml`](../../.github/workflows/android.yml) generates the differential corpus, runs
`./gradlew test assembleDebug` and uploads the debug APK as an artifact. With the upload key (below) it also builds
the signed release APK and bundle, checks their certificate against `upload-certificate.sha256`, and starts the
shrunk (R8) APK on an Android 14 emulator: `scripts/smoke-test.sh` shares "Toshkent shahri" to the app and expects
"Toşkent şahri" on the screen without a crash. Releases ship that signed APK and the `.aab` for Google Play.

### Signing

Release builds are signed with the **upload key** (PKCS12, RSA 4096, alias `upload`, valid until 2056). Google Play
re-signs the app for users with its own app-signing key (Play App Signing), so a lost upload key can be replaced
through Play Console support, but keep a backup of it. The key never goes into the repository: Gradle reads it from
the environment.

```bash
export UZT_UPLOAD_STORE_FILE=/path/to/uztranslit-upload.jks UZT_UPLOAD_STORE_PASSWORD=…   # UZT_UPLOAD_KEY_ALIAS: upload
./gradlew assembleRelease bundleRelease     # app/build/outputs/apk/release/app-release.apk, bundle/release/app-release.aab
```

CI gets the same from the secrets `ANDROID_UPLOAD_KEYSTORE_BASE64` (the .jks, base64) and
`ANDROID_UPLOAD_STORE_PASSWORD`; pull requests from forks have no secrets and build debug only. Certificate SHA-256:
`43:7D:47:AF:8E:AA:AC:FD:97:3A:C3:33:54:19:09:42:80:F5:D2:43:C8:05:2D:AF:A4:54:A2:97:3C:29:05:AE`
(`upload-certificate.sha256`; Play Console shows it under *Test and release ▸ App integrity* after the first upload).

Releases up to 1.2.0 were signed with a debug key: Android refuses to update those with the signed APK, so uninstall
the old version once.

### What the tests check

* `core` — `FixturesTest` runs every entry of `spec/fixtures.json` (196 cases, 8 roundtrips, 9 detections,
  3 optional features: **216/216**). `DifferentialTest` compares the engine with the reference
  `core/js/uztranslit.js` on `build/differential.json` (20,000 random conversions in ten directions with random
  options, plus 2,000 detections); without that file it is skipped with a message. `DictionaryTest` reads SPEC §6
  from `spec/SPEC.md` and requires `UzDictionary` to hold exactly those entries in that order. `UzTranslitTest`
  covers the API (defaults, option checks, unknown directions, a Turkish default locale, surrogate pairs).
  The Gradle task `copyConformanceData` copies `spec/fixtures.json`, `spec/SPEC.md` and `build/differential.json`
  into a generated test-resources directory at build time; no case is ever copied into the source tree.
* `app` — JVM tests of the `ConverterViewModel` (live conversion, auto-detection, swap, settings persisted through
  a fake repository, the long-text debounce, shared-file conversion and saving, error cases), the pure helpers
  (direction choice, counts, file names, text decoding) and the real DataStore settings repository.

## Features

* **Main screen** — source: Avto / Кирилл / Lotin 1995 / Yangi lotin; target: Кирилл / Lotin 1995 / Yangi lotin;
  swap (the result becomes the input and the direction turns round); live conversion (texts over 50,000 characters
  convert once typing pauses for 250 ms); paste, clear, copy, share; character and word counts; the detected
  alphabet; an "Oddiy apostrof ( ' )" switch for ASCII ' instead of ʻ ʼ. With "Avto", a text already in the target
  alphabet goes to the other family (Latin → Кирилл, Кирилл → Yangi lotin), as on latin.jaybi.uz.
* **Selected text in any app** — "UzTranslit bilan oʻgirish" in the text selection menu (`ACTION_PROCESS_TEXT`)
  opens a small dialog with the converted text and a target choice. **Oʻrniga qoʻyish** (Replace) returns it in
  `EXTRA_PROCESS_TEXT`, which replaces the selection; when the app marks the text read-only
  (`EXTRA_PROCESS_TEXT_READONLY`) the dialog offers copy and share instead.
* **Share sheet** — shared text opens in the editor. A shared `.txt`, `.md`, `.srt` or `.csv` file (also through
  the file button on the main screen) is decoded (UTF-8, UTF-8/UTF-16 with BOM; other bytes are read as
  Windows-1251), its alphabet detected, converted and offered for saving through the Storage Access Framework
  (`ACTION_CREATE_DOCUMENT`) as the original name plus the target: `hujjat.txt` → `hujjat-new.txt`
  (`-cyr`, `-lat`, `-new`; an existing suffix is replaced). The encoding and BOM are kept; Windows-1251 files are
  written as UTF-8. Up to 10 MB; HTML, JSON, Office files and the like are refused because converting them as plain
  text would break their markup.
* **Quick Settings tile** "Buferni oʻgirish" — converts the clipboard to the target alphabet from the settings.
  Since Android 10 only the focused app may read the clipboard, so the tile starts an invisible translucent
  activity that reads, converts and writes the clipboard as soon as it has window focus, then closes
  (`startActivityAndCollapse(PendingIntent)` on Android 14+).
* **Settings** (DataStore) — target alphabet (also used by the tile, the selection dialog and shared files),
  apostrophe style, loanword dictionary (obyekt → объект), ўъ → oʻ (`dropHardSignAfterO`). The other options keep
  the SPEC defaults (`tsFinal`, `skipUrls`).
* **Languages** — `values` (English), `values-uz` (Uzbek, Latin 1995 with ʻ U+02BB and ʼ U+02BC), `values-ru`;
  Android 13+ also lists the app under per-app languages.

## The engine (`core`)

`UzTranslit.convert(text, from, to, options)`, `detect(text)` and `cyrToLat`, `cyrToNew`, `latToCyr`, `newToCyr`,
`latToNew`, `newToLat`; `UzTranslit.Options` has the SPEC defaults (okina U+02BB, tutuq U+02BC, all four flags
on; okina and tutuq are empty or one character). It is the reference implementation function by function, with
the SPEC §5 helper names (`isCyr`, `isLat`, `isApos`, `nextLetterIsUpper`, `caseOut`, `cyrToLatin`,
`latinToCyrScan`, `convertWordWithDict`, `latToNew`, `newToLat`, `detect`):

* index-based scanners over UTF-16 code units (`Char`), exactly like JavaScript strings;
* case mapping only through the letter tables, never `lowercase()`/`uppercase()` (no Turkish İ/ı surprises);
  the reference's `substr(…).toLowerCase()` test for -tsiya/-tsion is ASCII lowering, which is equivalent;
* URL/e-mail/handle protection reproduces `/(https?:\/\/|www\.)\S+|\S+@\S+\.\S+|@\w+/g` by scanning, with
  JavaScript's `\s` (including U+00A0, U+2028, U+FEFF … but not U+0085 or U+180E) and ASCII-only `\w`.

A conversion rule changes in `spec/` first, then in every port (see `CLAUDE.md`).

## Toolchain

| | Version |
|---|---|
| Gradle (wrapper, checksum-pinned) | 9.8.1 |
| Android Gradle plugin (built-in Kotlin) | 9.4.1 |
| Kotlin | 2.4.21 |
| Compose BOM | 2026.09.00 (Compose 1.12, Material 3 1.4) |
| JDK | 21 in CI; Java/Kotlin target 17, so any JDK from 17 on builds and tests it |
| compileSdk / targetSdk / minSdk | 37 / 37 / 24 |

Versions live in `gradle/libs.versions.toml`. `gradle.properties` keeps the build modest (4 workers, 2 GB for the
Gradle and Kotlin daemons) because the build machine is shared.
