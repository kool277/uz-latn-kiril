#!/usr/bin/env python3
"""Puts the UzTranslit ribbon tab into a macro-enabled Office file that already holds the UzTranslit and
UzTranslitRibbon modules (Word .dotm/.docm, Excel .xlam/.xlsm, PowerPoint .ppam/.pptm). Office cannot add a ribbon
to a file itself, and a VBA project cannot be written outside Office, so the steps are: import the modules and save
in Office, then run this, then load the file as a template / add-in (docs/OFFICE_INSTALL.md).

usage: python3 tools/add_ribbon.py FILE [--out NEW_FILE] [--force]
  --force  also for a file without a VBA project (the buttons then have no macro to call: for tests only)

Adds customUI/customUI.xml (Office 2007) and customUI/customUI14.xml (2010 and later) with their images, the two
package relationships and the png content type. Running it again replaces the ribbon; nothing else in the file
changes.
"""
import argparse
import os
import re
import shutil
import sys
import tempfile
import zipfile
from xml.sax.saxutils import quoteattr

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RIBBON = os.path.join(ROOT, "office-vba", "ribbon")
REL_2006 = "http://schemas.microsoft.com/office/2006/relationships/ui/extensibility"
REL_2007 = "http://schemas.microsoft.com/office/2007/relationships/ui/extensibility"
REL_IMAGE = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/image"
PKG_RELS = "http://schemas.openxmlformats.org/package/2006/relationships"


def ribbon_parts(ribbon=RIBBON):
    parts = {}
    images = sorted(f for f in os.listdir(os.path.join(ribbon, "images")) if f.endswith(".png"))
    rels = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<Relationships xmlns="%s">' % PKG_RELS
            + "".join('<Relationship Id=%s Type="%s" Target="images/%s"/>' % (quoteattr(f[:-4]), REL_IMAGE, f) for f in images)
            + "</Relationships>")
    for name in ("customUI.xml", "customUI14.xml"):
        with open(os.path.join(ribbon, name), "rb") as f:
            parts["customUI/" + name] = f.read()
        parts["customUI/_rels/%s.rels" % name] = rels.encode("utf-8")
    for img in images:
        with open(os.path.join(ribbon, "images", img), "rb") as f:
            parts["customUI/images/" + img] = f.read()
    return parts


def patch_root_rels(xml):
    # drop an earlier ribbon, then point at ours
    xml = re.sub(r'<Relationship\b[^>]*Type="(%s|%s)"[^>]*/>' % (re.escape(REL_2006), re.escape(REL_2007)), "", xml)
    ids = set(re.findall(r'\bId="([^"]+)"', xml))
    def free(base):
        i = 1
        while "%s%d" % (base, i) in ids:
            i += 1
        ids.add("%s%d" % (base, i))
        return "%s%d" % (base, i)
    add = ('<Relationship Id="%s" Type="%s" Target="customUI/customUI.xml"/>' % (free("uzRibbon"), REL_2006)
           + '<Relationship Id="%s" Type="%s" Target="customUI/customUI14.xml"/>' % (free("uzRibbon"), REL_2007))
    return xml.replace("</Relationships>", add + "</Relationships>")


def patch_content_types(xml):
    if not re.search(r'<Default\b[^>]*Extension="png"', xml, re.I):
        xml = xml.replace("</Types>", '<Default Extension="png" ContentType="image/png"/></Types>')
    return xml


def add_ribbon(src, dst, force=False, ribbon=RIBBON):
    """ribbon: the folder with customUI*.xml and images/ (the Office installer bundles its own copy)"""
    with zipfile.ZipFile(src) as z:
        names = z.namelist()
        if "[Content_Types].xml" not in names or "_rels/.rels" not in names:
            raise SystemExit("%s is not an Office Open XML file" % src)
        if not any(n.endswith("vbaProject.bin") for n in names) and not force:
            raise SystemExit("%s has no VBA project: import UzTranslit.bas and UzTranslitRibbon.bas in Office and save it as a "
                             "macro-enabled file (.dotm, .xlam, .ppam ...) first" % src)
        parts = ribbon_parts(ribbon)
        fd, tmp = tempfile.mkstemp(suffix=".zip", dir=os.path.dirname(os.path.abspath(dst)))
        os.close(fd)
        try:
            with zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as out:
                for info in z.infolist():
                    if info.filename.startswith("customUI/"):
                        continue                                   # an earlier ribbon (ours or another)
                    data = z.read(info.filename)
                    if info.filename == "_rels/.rels":
                        data = patch_root_rels(data.decode("utf-8")).encode("utf-8")
                    elif info.filename == "[Content_Types].xml":
                        data = patch_content_types(data.decode("utf-8")).encode("utf-8")
                    out.writestr(info, data)
                for name, data in parts.items():
                    out.writestr(name, data)
            shutil.move(tmp, dst)
        except BaseException:
            os.remove(tmp)
            raise
    return dst


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("file")
    ap.add_argument("--out")
    ap.add_argument("--force", action="store_true")
    a = ap.parse_args()
    dst = add_ribbon(a.file, a.out or a.file, a.force)
    print("UzTranslit ribbon added:", dst)


if __name__ == "__main__":
    sys.exit(main())
