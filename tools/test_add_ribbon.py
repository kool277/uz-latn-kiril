#!/usr/bin/env python3
"""Tests tools/add_ribbon.py on the Word, Excel and PowerPoint fixtures, and that the ribbon and its VBA callback agree.
usage: python3 tools/test_add_ribbon.py        (LibreOffice, when installed, also opens every result)"""
import os
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
import xml.dom.minidom

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import add_ribbon  # noqa: E402

failures = []


def check(name, ok, detail=""):
    print("  %s %s%s" % ("ok  " if ok else "FAIL", name, "" if ok else "  " + str(detail)))
    if not ok:
        failures.append(name)


def ribbon_and_callback():
    ids, actions, images = set(), set(), set()
    for name in ("customUI.xml", "customUI14.xml"):
        d = xml.dom.minidom.parse(os.path.join(add_ribbon.RIBBON, name))
        for b in d.getElementsByTagName("button"):
            ids.add(b.getAttribute("id"))
            actions.add(b.getAttribute("onAction"))
        for tag in ("button", "menu"):
            images |= {e.getAttribute("image") for e in d.getElementsByTagName(tag) if e.getAttribute("image")}
    bas = open(os.path.join(ROOT, "office-vba", "UzTranslitRibbon.bas"), encoding="ascii").read()
    cases = set(re.findall(r'Case "(\w+)":', bas))
    check("every button calls UzRibbon_OnAction", actions == {"UzRibbon_OnAction"}, actions)
    check("UzRibbon_OnAction handles exactly the ribbon's buttons", ids == cases, ids ^ cases)
    main = open(os.path.join(ROOT, "office-vba", "UzTranslit.bas"), encoding="ascii").read()
    called = set(re.findall(r'Case "\w+": (\w+)', bas))
    missing = {c for c in called if not re.search(r"^Public Sub %s\b" % c, main, re.M)}
    check("every called macro is a Public Sub of UzTranslit.bas", not missing, missing)
    have = {f[:-4] for f in os.listdir(os.path.join(add_ribbon.RIBBON, "images"))}
    check("every image exists", images <= have, images - have)


def package(path):
    with zipfile.ZipFile(path) as z:
        return {n: z.read(n) for n in z.namelist()}


def soffice_opens(path, tmp):
    if not shutil.which("soffice"):
        return True
    out = os.path.join(tmp, "pdf")
    profile = "file://" + os.path.join(tmp, "profile")
    subprocess.run(["soffice", "-env:UserInstallation=" + profile, "--headless", "--convert-to", "pdf", "--outdir", out, path],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=180)
    return os.path.exists(os.path.join(out, os.path.splitext(os.path.basename(path))[0] + ".pdf"))


def file_tests(fixture, tmp):
    print("== " + fixture)
    src = os.path.join(ROOT, "web", "test", "fixtures", "docs", fixture)
    dst = os.path.join(tmp, "ribbon-" + fixture)
    try:
        add_ribbon.add_ribbon(src, dst)
        check("refuses a file without a VBA project", False, "no error")
    except SystemExit:
        check("refuses a file without a VBA project", True)
    add_ribbon.add_ribbon(src, dst, force=True)
    add_ribbon.add_ribbon(dst, dst, force=True)  # a second run replaces, never duplicates
    before, after = package(src), package(dst)
    check("every original part is unchanged", all(after[n] == before[n] for n in before if n not in ("_rels/.rels", "[Content_Types].xml")))
    for part in ("customUI/customUI.xml", "customUI/customUI14.xml", "customUI/_rels/customUI.xml.rels",
                 "customUI/_rels/customUI14.xml.rels", "customUI/images/to_new.png"):
        check("has " + part, part in after)
    rels = xml.dom.minidom.parseString(after["_rels/.rels"])
    targets = sorted(r.getAttribute("Target") for r in rels.getElementsByTagName("Relationship")
                     if "/ui/extensibility" in r.getAttribute("Type"))
    check("exactly one relationship per ribbon file", targets == ["customUI/customUI.xml", "customUI/customUI14.xml"], targets)
    ids = [r.getAttribute("Id") for r in rels.getElementsByTagName("Relationship")]
    check("relationship ids unique", len(ids) == len(set(ids)), ids)
    types = xml.dom.minidom.parseString(after["[Content_Types].xml"])
    png = [d for d in types.getElementsByTagName("Default") if d.getAttribute("Extension").lower() == "png"]
    check("one png content type", len(png) == 1)
    for n in after:
        if n.endswith((".xml", ".rels")):
            xml.dom.minidom.parseString(after[n])  # raises on malformed XML
    check("LibreOffice still opens it", soffice_opens(dst, tmp))


def main():
    print("== ribbon XML and UzTranslitRibbon.bas")
    ribbon_and_callback()
    tmp = tempfile.mkdtemp(prefix="uzribbon-", dir=os.path.join(ROOT, "build") if os.path.isdir(os.path.join(ROOT, "build")) else None)
    try:
        for f in ("writer.docx", "calc.xlsx", "impress.pptx"):
            file_tests(f, tmp)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print("%d failed" % len(failures) if failures else "add_ribbon: all checks passed")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
