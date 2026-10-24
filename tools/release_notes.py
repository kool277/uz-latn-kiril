#!/usr/bin/env python3
"""Release notes for a tag: what is attached, how to install it, and what each platform is checked against.
usage: python3 tools/release_notes.py v1.0.0 [ASSET_DIR]     (with ASSET_DIR: also the SHA-256 of every file)"""
import hashlib
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main():
    tag = sys.argv[1] if len(sys.argv) > 1 else "v0.0.0"
    assets = sys.argv[2] if len(sys.argv) > 2 else None
    fx = json.load(open(os.path.join(ROOT, "spec", "fixtures.json"), encoding="utf-8"))
    total = sum(len(fx[k]) for k in ("cases", "roundtrips", "detect", "optional"))
    lo_total = len(fx["cases"]) + len(fx["roundtrips"]) + len(fx["detect"]) + sum(1 for o in fx["optional"] if o["feature"] == "asciiApostrophe")
    out = [
        "UzTranslit %s — Oʻzbek alifbo konvertori: Кирилл ⇄ Lotin 1995 ⇄ Yangi lotin (Ö Ğ Ş Ç)." % tag,
        "",
        "Every file below was built by this release's workflow after every suite passed. The web version is https://latin.jaybi.uz.",
        "",
        "| File | For | Install |",
        "|---|---|---|",
        "| `UzTranslit-*-setup.exe` | Windows 10/11 | run the installer (unsigned: *More info ▸ Run anyway*) |",
        "| `UzTranslit-*.dmg` | macOS 12+ | open, drag to Applications; first start: right-click ▸ Open (not notarized) |",
        "| `UzTranslit-*.AppImage` | Linux (glibc 2.39+) | `chmod +x` and run |",
        "| `UzTranslit-*-android.apk` | Android 7+ | allow installing from this source; signed with a debug key, so it replaces no store version |",
        "| `UzTranslit.bas`, `UzTranslitRibbon.bas`, `UzTranslit-ribbon-kit.zip` | Word, Excel, PowerPoint 97–2026 | docs/OFFICE_INSTALL.md |",
        "| `uztranslit-office-addin.xml` | Office on the web, Mac, iPad, Microsoft 365 | platforms/office-addin/README.md (sideload) |",
        "| `uztranslit-libreoffice.oxt` / `-python.oxt` | LibreOffice | *Tools ▸ Extension Manager ▸ Add* |",
        "| `UzTranslitLO.bas` | LibreOffice Calc formulas (`=UZCONVERT()`) | import into *My Macros ▸ Standard* |",
        "",
        "Conformance: `spec/fixtures.json` has **%d checks** (%d cases, %d round trips, %d detections, %d optional), and a"
        % (total, len(fx["cases"]), len(fx["roundtrips"]), len(fx["detect"]), len(fx["optional"])),
        "differential corpus of 20,000 random conversions and 2,000 detections is generated from the reference core for every run.",
        "",
        "| Platform | Fixtures | Differential | Also |",
        "|---|---|---|---|",
        "| JavaScript (reference), Python | %d/%d | 22,000 (Python) | |" % (total, total),
        "| WebAssembly + wasm2js (web app) | %d/%d each | 40,000 per build | document formats, 507 engine tests, Playwright |" % (total, total),
        "| LibreOffice Basic = Office VBA engine | %d/%d | 3,500 | both extensions end to end in Writer, Calc, Impress |" % (lo_total, lo_total),
        "| Kotlin (Android) | %d/%d | 22,000 | app unit tests |" % (total, total),
        "| Swift (iOS, macOS) | %d/%d | 22,000 | apps built with Xcode in CI (not distributed here: needs an Apple team) |" % (total, total),
        "| C++ / Qt 6 (desktop) | %d/%d | 22,000 | CLI, offscreen GUI, documents, translations on Linux, Windows, macOS |" % (total, total),
        "| Office add-in | — | word-by-word = whole text on the corpus | fake hosts, task pane in Chromium |",
        "",
        "Not verified by CI: Word/Excel/PowerPoint themselves (the macros are compiled in LibreOffice's VBA mode and linted),",
        "a real Office host for the add-in, devices for the apps. Reports with a sample file are welcome.",
    ]
    if assets:
        out += ["", "SHA-256:", "", "```"]
        for f in sorted(os.listdir(assets)):
            p = os.path.join(assets, f)
            if os.path.isfile(p):
                out.append("%s  %s" % (hashlib.sha256(open(p, "rb").read()).hexdigest(), f))
        out.append("```")
    print("\n".join(out))


if __name__ == "__main__":
    main()
