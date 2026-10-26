#!/usr/bin/env python3
"""Builds UzTranslit-Office-Setup.exe on Windows: PyInstaller, one file, no console window, with the VBA modules,
the ribbon and its icons inside.
usage (Windows, Python 3.9+):  py -m pip install -r platforms/office-installer/requirements.txt
                               py platforms/office-installer/build.py        → build/office-installer/dist/
This is `pyinstaller --noconsole --onefile installer.py` plus the bundled files (--add-data), tools/add_ribbon.py
(--paths) and an icon made from the web app's."""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(ROOT, "build", "office-installer")


def icon():
    """web/public/icons/icon-512x512.png → .ico (Pillow); None when Pillow or the png is missing."""
    try:
        from PIL import Image
    except ImportError:
        return None
    src = os.path.join(ROOT, "web", "public", "icons", "icon-512x512.png")
    if not os.path.isfile(src):
        return None
    dst = os.path.join(OUT, "uztranslit.ico")
    os.makedirs(OUT, exist_ok=True)
    Image.open(src).save(dst, sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    return dst


def main():
    if sys.platform != "win32":
        raise SystemExit("build.py runs on Windows (PyInstaller does not cross-compile); CI builds the exe in release.yml")
    import PyInstaller.__main__
    data = [
        (os.path.join(ROOT, "office-vba", "UzTranslit.bas"), "office-vba"),
        (os.path.join(ROOT, "office-vba", "UzTranslitRibbon.bas"), "office-vba"),
        (os.path.join(ROOT, "office-vba", "ribbon"), os.path.join("office-vba", "ribbon")),
    ]
    args = [
        os.path.join(HERE, "installer.py"),
        "--name", "UzTranslit-Office-Setup",
        "--noconsole", "--onefile", "--noconfirm", "--clean",
        "--paths", os.path.join(ROOT, "tools"),
        "--hidden-import", "add_ribbon",
        "--distpath", os.path.join(OUT, "dist"),
        "--workpath", os.path.join(OUT, "work"),
        "--specpath", OUT,
    ]
    for src, dest in data:
        args += ["--add-data", "%s%s%s" % (src, os.pathsep, dest)]
    ico = icon()
    if ico:
        args += ["--icon", ico]
    PyInstaller.__main__.run(args)
    print("built", os.path.join(OUT, "dist", "UzTranslit-Office-Setup.exe"))


if __name__ == "__main__":
    main()
