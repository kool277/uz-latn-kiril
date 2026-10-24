#!/usr/bin/env python3
"""Assemble libreoffice/uztranslit-libreoffice.oxt from the Python core + UNO glue + metadata.
    python3 tools/build_oxt.py
"""
import os
import re
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CORE = os.path.join(ROOT, "core", "python", "uztranslit.py")
GLUE = os.path.join(ROOT, "libreoffice", "extension", "uztranslit_lo_glue.py")
OUT_DIR = os.path.join(ROOT, "libreoffice")
OXT_NAME = "uztranslit-libreoffice-python.oxt"
OXT_BASIC = "uztranslit-libreoffice.oxt"
LIB = "UzTranslit"
MODULE = "UzTranslitLO"
VERSION = re.search(r'VERSION = "([^"]+)"', open(CORE, encoding="utf-8").read()).group(1)
SCRIPT = "uztranslit_lo.py"
SCRIPT_DIR = "python"
IDENT = "uz.jaybi.uztranslit"


def script_url(func):
    return "vnd.sun.star.script:%s|%s|%s$%s?language=Python&amp;location=user:uno_packages" % (OXT_NAME, SCRIPT_DIR, SCRIPT, func)


MENU = [
    ("auto_to_new", "Avto → Yangi lotin (Ö Ğ Ş Ç)"),
    ("auto_to_lat", "Avto → Lotin 1995"),
    ("auto_to_cyr", "Avto → Кирилл"),
    (None, None),
    ("lat_to_new", "Lotin 1995 → Yangi lotin"),
    ("new_to_lat", "Yangi lotin → Lotin 1995"),
    ("cyr_to_lat", "Кирилл → Lotin 1995"),
    ("cyr_to_new", "Кирилл → Yangi lotin"),
    ("lat_to_cyr", "Lotin 1995 → Кирилл"),
    ("new_to_cyr", "Yangi lotin → Кирилл"),
    (None, None),
    ("self_test", "Self-test / Oʻz-oʻzini tekshirish"),
]


def addons_xcu():
    items = []
    for i, (func, label) in enumerate(MENU):
        if func is None:
            items.append('      <node oor:name="m%02d" oor:op="replace">\n        <prop oor:name="URL" oor:type="xs:string"><value>private:separator</value></prop>\n      </node>' % i)
            continue
        items.append(
            '      <node oor:name="m%02d" oor:op="replace">\n'
            '        <prop oor:name="URL" oor:type="xs:string"><value>%s</value></prop>\n'
            '        <prop oor:name="Title" oor:type="xs:string"><value xml:lang="en-US">%s</value></prop>\n'
            '        <prop oor:name="Target" oor:type="xs:string"><value>_self</value></prop>\n'
            '        <prop oor:name="Context" oor:type="xs:string"><value>com.sun.star.text.TextDocument,com.sun.star.sheet.SpreadsheetDocument,com.sun.star.presentation.PresentationDocument,com.sun.star.drawing.DrawingDocument</value></prop>\n'
            '      </node>' % (i, script_url(func), label))
    return ('<?xml version="1.0" encoding="UTF-8"?>\n'
            '<oor:component-data xmlns:oor="http://openoffice.org/2001/registry" xmlns:xs="http://www.w3.org/2001/XMLSchema" oor:name="Addons" oor:package="org.openoffice.Office">\n'
            '  <node oor:name="AddonUI">\n'
            '    <node oor:name="OfficeMenuBar">\n'
            '      <node oor:name="%s.menu" oor:op="replace">\n'
            '        <prop oor:name="Title" oor:type="xs:string"><value xml:lang="en-US">UzTranslit</value></prop>\n'
            '        <prop oor:name="Target" oor:type="xs:string"><value>_self</value></prop>\n'
            '        <node oor:name="Submenu">\n%s\n        </node>\n'
            '      </node>\n'
            '    </node>\n'
            '  </node>\n'
            '</oor:component-data>\n') % (IDENT, "\n".join(items).replace("\n      <node", "\n          <node"))


def description_xml():
    return ('<?xml version="1.0" encoding="UTF-8"?>\n'
            '<description xmlns="http://openoffice.org/extensions/description/2006" xmlns:xlink="http://www.w3.org/1999/xlink">\n'
            '  <identifier value="%s"/>\n'
            '  <version value="%s"/>\n'
            '  <platform value="all"/>\n'
            '  <dependencies><OpenOffice.org-minimal-version value="4.1" dependency:name="OpenOffice.org 4.1" xmlns:dependency="http://openoffice.org/extensions/description/2006"/></dependencies>\n'
            '  <display-name><name lang="en-US">UzTranslit — Oʻzbek alifbo konvertori (Кирилл / Lotin 1995 / Ö Ğ Ş Ç)</name></display-name>\n'
            '  <publisher><name xlink:href="https://latin.jaybi.uz" lang="en-US">latin.jaybi.uz</name></publisher>\n'
            '  <extension-description><src xlink:href="description/desc_en.txt" lang="en-US"/></extension-description>\n'
            '</description>\n') % (IDENT, VERSION)


def manifest_xml():
    return ('<?xml version="1.0" encoding="UTF-8"?>\n'
            '<manifest:manifest xmlns:manifest="http://openoffice.org/2001/manifest">\n'
            '  <manifest:file-entry manifest:media-type="application/vnd.sun.star.configuration-data" manifest:full-path="Addons.xcu"/>\n'
            '  <manifest:file-entry manifest:media-type="application/vnd.sun.star.framework-script" manifest:full-path="%s/"/>\n'
            '</manifest:manifest>\n') % SCRIPT_DIR


def build():
    core = open(CORE, encoding="utf-8").read()
    core = core.split('\nif __name__ == "__main__":')[0]  # drop the CLI entry point
    glue = open(GLUE, encoding="utf-8").read()
    script = core + "\n\n" + glue
    out = os.path.join(OUT_DIR, OXT_NAME)
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("META-INF/manifest.xml", manifest_xml())
        z.writestr("description.xml", description_xml())
        z.writestr("Addons.xcu", addons_xcu())
        z.writestr(SCRIPT_DIR + "/" + SCRIPT, script)
        z.writestr("description/desc_en.txt",
                   "UzTranslit %s\nConverts Uzbek text between Cyrillic, Latin 1995 and the 2026 Latin alphabet "
                   "(O'RQ-1184: Oʻ→Ö, Gʻ→Ğ, Sh→Ş, Ch→Ç) in Writer, Calc, Impress and Draw.\n"
                   "Menu: Tools ▸ UzTranslit. Converts the selection, or the whole document when nothing is selected.\n"
                   "Web version: https://latin.jaybi.uz\n" % VERSION)
    # also keep the assembled script next to the sources for inspection
    open(os.path.join(ROOT, "libreoffice", "extension", SCRIPT), "w", encoding="utf-8").write(script)
    print("built", out, os.path.getsize(out), "bytes")
    return out



def basic_url(func):
    return "vnd.sun.star.script:%s.%s.%s?language=Basic&amp;location=application" % (LIB, MODULE, func)


BASIC_NAMES = {"auto_to_new": "UzLO_AutoToNew", "auto_to_lat": "UzLO_AutoToLat", "auto_to_cyr": "UzLO_AutoToCyr",
               "lat_to_new": "UzLO_LatToNew", "new_to_lat": "UzLO_NewToLat", "cyr_to_lat": "UzLO_CyrToLat",
               "cyr_to_new": "UzLO_CyrToNew", "lat_to_cyr": "UzLO_LatToCyr", "new_to_cyr": "UzLO_NewToCyr",
               "self_test": "UzSelfTest"}
BASIC_MENU = [(None if f is None else BASIC_NAMES[f], l) for f, l in MENU]


def addons_xcu_basic():
    items = []
    for i, (func, label) in enumerate(BASIC_MENU):
        if func is None:
            items.append('          <node oor:name="m%02d" oor:op="replace">\n            <prop oor:name="URL" oor:type="xs:string"><value>private:separator</value></prop>\n          </node>' % i)
            continue
        items.append(
            '          <node oor:name="m%02d" oor:op="replace">\n'
            '            <prop oor:name="URL" oor:type="xs:string"><value>%s</value></prop>\n'
            '            <prop oor:name="Title" oor:type="xs:string"><value xml:lang="en-US">%s</value></prop>\n'
            '            <prop oor:name="Target" oor:type="xs:string"><value>_self</value></prop>\n'
            '            <prop oor:name="Context" oor:type="xs:string"><value>com.sun.star.text.TextDocument,com.sun.star.sheet.SpreadsheetDocument,com.sun.star.presentation.PresentationDocument,com.sun.star.drawing.DrawingDocument</value></prop>\n'
            '          </node>' % (i, basic_url(func), label))
    return ('<?xml version="1.0" encoding="UTF-8"?>\n'
            '<oor:component-data xmlns:oor="http://openoffice.org/2001/registry" xmlns:xs="http://www.w3.org/2001/XMLSchema" oor:name="Addons" oor:package="org.openoffice.Office">\n'
            '  <node oor:name="AddonUI">\n'
            '    <node oor:name="OfficeMenuBar">\n'
            '      <node oor:name="%s.menu" oor:op="replace">\n'
            '        <prop oor:name="Title" oor:type="xs:string"><value xml:lang="en-US">UzTranslit</value></prop>\n'
            '        <prop oor:name="Target" oor:type="xs:string"><value>_self</value></prop>\n'
            '        <node oor:name="Submenu">\n%s\n        </node>\n'
            '      </node>\n'
            '    </node>\n'
            '  </node>\n'
            '</oor:component-data>\n') % (IDENT, "\n".join(items))


XBA = ('<?xml version="1.0" encoding="UTF-8"?>\n'
       '<!DOCTYPE script:module PUBLIC "-//OpenOffice.org//DTD OfficeDocument 1.0//EN" "module.dtd">\n'
       '<script:module xmlns:script="http://openoffice.org/2000/script" script:name="%s" script:language="StarBasic">%s</script:module>\n')


def build_basic():
    basic_src = open(os.path.join(ROOT, "libreoffice", "UzTranslitLO.bas"), encoding="utf-8").read()
    esc = basic_src.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    out = os.path.join(OUT_DIR, OXT_BASIC)
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("META-INF/manifest.xml",
                   '<?xml version="1.0" encoding="UTF-8"?>\n'
                   '<manifest:manifest xmlns:manifest="http://openoffice.org/2001/manifest">\n'
                   '  <manifest:file-entry manifest:media-type="application/vnd.sun.star.configuration-data" manifest:full-path="Addons.xcu"/>\n'
                   '  <manifest:file-entry manifest:media-type="application/vnd.sun.star.basic-library" manifest:full-path="%s/"/>\n'
                   '</manifest:manifest>\n' % LIB)
        z.writestr("description.xml", description_xml().replace(IDENT + '"', IDENT + '"', 1))
        z.writestr("Addons.xcu", addons_xcu_basic())
        z.writestr(LIB + "/script.xlb",
                   '<?xml version="1.0" encoding="UTF-8"?>\n'
                   '<!DOCTYPE library:library PUBLIC "-//OpenOffice.org//DTD OfficeDocument 1.0//EN" "library.dtd">\n'
                   '<library:library xmlns:library="http://openoffice.org/2000/library" library:name="%s" library:readonly="false" library:passwordprotected="false">\n'
                   ' <library:element library:name="%s"/>\n'
                   '</library:library>\n' % (LIB, MODULE))
        z.writestr(LIB + "/dialog.xlb",
                   '<?xml version="1.0" encoding="UTF-8"?>\n'
                   '<!DOCTYPE library:library PUBLIC "-//OpenOffice.org//DTD OfficeDocument 1.0//EN" "library.dtd">\n'
                   '<library:library xmlns:library="http://openoffice.org/2000/library" library:name="%s" library:readonly="false" library:passwordprotected="false"/>\n' % LIB)
        z.writestr(LIB + "/" + MODULE + ".xba", XBA % (MODULE, esc))
        z.writestr("description/desc_en.txt",
                   "UzTranslit %s (Basic edition, no Python needed)\nConverts Uzbek text between Cyrillic, Latin 1995 and the 2026 Latin alphabet "
                   "(O'RQ-1184: Oʻ→Ö, Gʻ→Ğ, Sh→Ş, Ch→Ç) in Writer, Calc, Impress and Draw.\n"
                   "Menu: Tools ▸ UzTranslit. Calc formula: =UZCONVERT(A1;\"lat\";\"new\")\n"
                   "Web version: https://latin.jaybi.uz\n" % VERSION)
    print("built", out, os.path.getsize(out), "bytes")
    return out


if __name__ == "__main__":
    build()
    build_basic()
