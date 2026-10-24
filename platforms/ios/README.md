# UzTranslit for iOS and macOS

Swift port of the converter (`spec/SPEC.md`) and the Apple apps: an iPhone/iPad app with a Share extension and an
Action extension, and a native macOS app with a Services menu item. All six directions between Cyrillic, Latin 1995
and Latin 2026 (Oʻ → Ö, Gʻ → Ğ, Sh → Ş, Ch → Ç), with auto-detection.

| Part | Path | Status |
|---|---|---|
| Swift package `UzTranslitCore` (engine, pure Swift, no Foundation) | `UzTranslitCore/Sources/UzTranslitCore` | 216/216 fixtures ✔, 20,000 + 2,000 differential checks vs `core/js` ✔ (Linux, Swift 6.0 and 6.4) |
| `UzTranslitKit` (settings, counts, text files; shared by the apps) | `UzTranslitCore/Sources/UzTranslitKit` | unit tests ✔ |
| iOS 16+ app, Share + Action extensions, macOS 13+ app (SwiftUI) | `Sources/`, `Resources/`, `Config/`, `project.yml` | built by CI (`.github/workflows/ios.yml`) |

## The engine

```swift
import UzTranslitCore

UzTranslit.convert("Toshkent shahri, Is'hoq", from: .lat, to: .new)   // "Toşkent şahri, Ishoq"
UzTranslit.convert("Ўзбекистон", from: .cyr, to: .lat)                 // "Oʻzbekiston"
UzTranslit.convert("Özbekiston", from: .auto, to: .cyr)                // "Ўзбекистон"
UzTranslit.detect("Toşkent")                                           // .new
UzTranslit.cyrToLat(text, options: .asciiApostrophe)                   // ' instead of ʻ ʼ
```

* API (SPEC §2): `convert(_:from:to:options:)`, `detect(_:)`, `cyrToLat`, `cyrToNew`, `latToCyr`, `newToCyr`,
  `latToNew`, `newToLat`; `Script` (`cyr`, `lat`, `new`), `SourceScript` (the same plus `auto`), `Options` with the
  spec defaults (okina U+02BB, tutuq U+02BC, `dropHardSignAfterO`, `tsFinal`, `dictionary`, `skipUrls` all on;
  okina/tutuq may be empty or `"'"`). `convertUTF16(_:from:to:options:)` works on `[UInt16]`.
* A faithful port of `core/js/uztranslit.js` with the same helper names (`isCyr`, `isLat`, `isApos`,
  `nextLetterIsUpper`, `caseOut`, `cyrToLatin`, `latinToCyrScan`, `convertWordWithDict`, `latToNew`, `newToLat`,
  `detect`). It works on **UTF-16 code units**, never on `Character`: a Swift `Character` is a grapheme cluster, and
  a combining mark or an emoji next to a letter would change what "the next character" is.
* `skipUrls` reproduces the JavaScript expression `/(https?:\/\/|www\.)\S+|\S+@\S+\.\S+|@\w+/g` with JavaScript's
  classes (`\s` = the ECMAScript white space set, `\w` = `[A-Za-z0-9_]`) as an index scanner (`SkipUrls.swift`, as in
  `core/wasm`), not with `NSRegularExpression`, whose classes differ.

## Tests

The tests read their data from the test bundle (`Bundle.module`); `scripts/sync-fixtures.sh` copies it in
(the copies are gitignored — never hand-copy cases):

```bash
node tools/make_differential.mjs          # from the repository root: build/differential.json (optional)
platforms/ios/scripts/sync-fixtures.sh    # spec/fixtures.json (+ build/differential.json) → test resources
cd platforms/ios/UzTranslitCore && swift test
```

Expected: `216 passed, 0 failed (fixtures.json v1.0.0 …)` from `FixturesTests` and
`conversions 20000 passed, 0 failed; detections 2000 passed, 0 failed` from `DifferentialTests` (skipped with a
message when `differential.json` was not synced). Without a local Swift toolchain (Linux), use Docker:

```bash
# from the repository root
docker run --rm -v "$PWD":/repo -w /repo/platforms/ios/UzTranslitCore --user "$(id -u):$(id -g)" -e HOME=/tmp \
  swift:6.4.1-noble swift test
```

`scripts/test.sh` does all three steps (and falls back to Docker when `swift` is not installed).
`python3 scripts/check-localizations.py` checks that every UI string has its Uzbek and Russian translation.

## The apps

* **Main screen** (iPhone, iPad, Mac): source (Avto / Кирилл / Lotin 1995 / Yangi lotin) and target pickers, swap
  (moves the result into the input and reverses the direction), live conversion (texts over 50,000 characters convert
  off the main thread once typing pauses), Paste (`PasteButton`, no paste prompt), Clear, Copy, Share (`ShareLink`),
  character and word counts, the ASCII-apostrophe switch; haptics on iPhone, Dynamic Type, dark mode. With Avto,
  text that is already in the target script goes to the other alphabet (as on the web site).
* **Settings**: default target alphabet, apostrophe style, dictionary, ўъ → oʻ (`dropHardSignAfterO`), word-final
  -ts, URL protection. Stored in the App Group `group.uz.jaybi.uztranslit` so the extensions use them.
* **Share extension** ("UzTranslit" in the share sheet): converts shared text or a shared `.txt` file (also `.md`,
  `.csv`, `.srt`, any plain-text file) to the default target; target picker, ASCII-apostrophe switch, Copy, Share,
  and Save for files (written as `name-new.txt` in the file's own encoding; Windows-1251 files become UTF-8). The
  activation rule is `NSExtensionActivationSupportsText` plus one file; the extension says so when the file is not
  plain text.
* **Action extension** ("Convert with UzTranslit" / "UzTranslit bilan oʻgirish"): converts the selected text; Done
  returns the converted text to the host app (`NSExtensionItem` with attributed and plain text) — apps that accept
  returned items replace the selection; Copy works everywhere.
* **macOS app**: the same window, Settings (⌘,), and **Services ▸ Convert to Yangi lotin**, which replaces the
  selected text in any app (`NSServices` in `Config/MacApp-Info.plist`, handled by `ServicesProvider`).
* UI languages: English, Uzbek (Latin 1995, with ʻ ʼ) and Russian (`Resources/Strings/Localizable.xcstrings`,
  plus `ServicesMenu.strings` and the Action extension's `InfoPlist.strings`). The app follows the system language
  or the per-app language in Settings.

## Building

```bash
brew install xcodegen
cd platforms/ios
xcodegen generate          # writes UzTranslit.xcodeproj from project.yml (not committed)
open UzTranslit.xcodeproj  # schemes: UzTranslit (iOS app + extensions), UzTranslitMac
```

Requires Xcode 16 or later (CI uses the latest stable Xcode on macOS 15). Without signing, e.g. for a quick check:

```bash
xcodebuild build -project UzTranslit.xcodeproj -scheme UzTranslit \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
xcodebuild build -project UzTranslit.xcodeproj -scheme UzTranslitMac \
  -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO
```

App targets compile in Swift 5 language mode (`SWIFT_VERSION` in `project.yml`); the package builds in Swift 6 mode.

## Signing and provisioning

The project leaves signing to you: `DEVELOPMENT_TEAM` is empty and `CODE_SIGN_STYLE` is Automatic.

1. **Apple Developer Program membership** (paid) — needed for App Groups, TestFlight and the App Store. A free
   Apple ID can run the macOS app and the iOS app on your own device, but without the App Group the extensions do
   not see the app's settings (they fall back to the defaults).
2. Set your team: in Xcode (Signing & Capabilities, for all four targets) or once in `project.yml`
   (`DEVELOPMENT_TEAM: ABCDE12345`) and run `xcodegen generate` again.
3. **Bundle identifiers**: `uz.jaybi.uztranslit` (iOS app), `uz.jaybi.uztranslit.share`,
   `uz.jaybi.uztranslit.action` (extensions; must stay prefixed by the app's id), `uz.jaybi.uztranslit.mac` (macOS
   app). Use your own prefix if you do not own `uz.jaybi` (change `project.yml`, `fastlane/Appfile` and the App Group).
4. **App Group** `group.uz.jaybi.uztranslit`: register it in Certificates, Identifiers & Profiles and enable the
   App Groups capability with this group for the three iOS identifiers (Xcode's automatic signing does this when
   you build with your team selected). The identifier is also in `Config/*.entitlements` and
   `UzTranslitKit/ConverterSettings.swift` (`AppGroup.identifier`).
5. **Provisioning**: automatic signing creates development and App Store profiles for the four identifiers. The
   macOS app is sandboxed (`Config/UzTranslitMac.entitlements`, Hardened Runtime on) and needs no App Group.

## TestFlight (fastlane)

`fastlane/Fastfile` has a `beta` lane: `xcodegen generate`, `build_app` (archive + App Store export with automatic,
API-key-based signing), `upload_to_testflight`.

```bash
cd platforms/ios
bundle install
ASC_KEY_ID=… ASC_ISSUER_ID=… ASC_KEY_PATH=~/keys/AuthKey_….p8 DEVELOPMENT_TEAM=ABCDE12345 bundle exec fastlane beta
```

* Create the key in App Store Connect ▸ Users and Access ▸ Integrations ▸ App Store Connect API (role App Manager
  or Admin, so that xcodebuild may create certificates and profiles: `-allowProvisioningUpdates` with
  `-authenticationKeyPath/-ID/-IssuerID`).
* On CI, put the key in a secret and pass `ASC_KEY_CONTENT` (set `ASC_KEY_BASE64=true` if it is base64-encoded)
  instead of `ASC_KEY_PATH`.
* Create the app record (`uz.jaybi.uztranslit`) in App Store Connect first. `BUILD_NUMBER` overrides the build
  number (default: latest TestFlight build + 1); the marketing version is `MARKETING_VERSION` in `project.yml`.
* Teams that keep certificates in a git repository can add `match(type: "appstore", readonly: true)` before
  `build_app` and drop the `-allowProvisioningUpdates` arguments.

## Layout

```
UzTranslitCore/            Swift package: UzTranslitCore (engine), UzTranslitKit (app logic), tests
Sources/Shared/            all four targets: script labels, clipboard, colours
Sources/App/               iOS and macOS apps: ConverterModel, ConverterView, SettingsView, haptics
Sources/iOSApp/ MacApp/    app entry points; MacApp/ServicesProvider.swift (Services menu)
Sources/Extensions/        both extensions: input loading, model, view; ShareExtension/, ActionExtension/
Resources/                 Strings/Localizable.xcstrings, asset catalogs, .lproj strings
Config/                    Info.plist and entitlements files
scripts/                   sync-fixtures.sh, test.sh, check-localizations.py, make-icons.py
fastlane/                  Fastfile (beta lane), Appfile
```
