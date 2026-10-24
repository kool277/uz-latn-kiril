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



class Oxt(zipfile.ZipFile):
    """A zip whose bytes depend only on its content (fixed entry dates): a rebuild without changes changes nothing."""
    def __init__(self, path):
        super().__init__(path, "w", zipfile.ZIP_DEFLATED)

    def writestr(self, name, data, *a, **k):
        if isinstance(name, str):
            name = zipfile.ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0))
            name.compress_type = zipfile.ZIP_DEFLATED
            name.external_attr = 0o644 << 16
        super().writestr(name, data, *a, **k)

def script_url(func):
    return "vnd.sun.star.script:%s|%s|%s$%s?language=Python&amp;location=user:uno_packages" % (OXT_NAME, SCRIPT_DIR, SCRIPT, func)


CONTEXT = ("com.sun.star.text.TextDocument,com.sun.star.sheet.SpreadsheetDocument,"
           "com.sun.star.presentation.PresentationDocument,com.sun.star.drawing.DrawingDocument")
# (function, icon, {language: title}); None = separator. The toolbar has the entries with an icon.
MENU = [
    ("auto_to_new", "to_new", {"en-US": "Auto → New Latin (Ö Ğ Ş Ç)", "uz": "Avto → Yangi lotin (Ö Ğ Ş Ç)", "ru": "Авто → новая латиница (Ö Ğ Ş Ç)"}),
    ("auto_to_lat", "to_lat", {"en-US": "Auto → Latin 1995", "uz": "Avto → Lotin 1995", "ru": "Авто → латиница 1995"}),
    ("auto_to_cyr", "to_cyr", {"en-US": "Auto → Cyrillic", "uz": "Avto → Кирилл", "ru": "Авто → кириллица"}),
    None,
    ("lat_to_new", None, {"en-US": "Latin 1995 → New Latin", "uz": "Lotin 1995 → Yangi lotin", "ru": "Латиница 1995 → новая латиница"}),
    ("new_to_lat", None, {"en-US": "New Latin → Latin 1995", "uz": "Yangi lotin → Lotin 1995", "ru": "Новая латиница → латиница 1995"}),
    ("cyr_to_lat", None, {"en-US": "Cyrillic → Latin 1995", "uz": "Кирилл → Lotin 1995", "ru": "Кириллица → латиница 1995"}),
    ("cyr_to_new", None, {"en-US": "Cyrillic → New Latin", "uz": "Кирилл → Yangi lotin", "ru": "Кириллица → новая латиница"}),
    ("lat_to_cyr", None, {"en-US": "Latin 1995 → Cyrillic", "uz": "Lotin 1995 → Кирилл", "ru": "Латиница 1995 → кириллица"}),
    ("new_to_cyr", None, {"en-US": "New Latin → Cyrillic", "uz": "Yangi lotin → Кирилл", "ru": "Новая латиница → кириллица"}),
    None,
    ("settings", None, {"en-US": "Settings…", "uz": "Sozlamalar…", "ru": "Настройки…"}),
    ("self_test", "self_test", {"en-US": "Self-test", "uz": "Oʻz-oʻzini tekshirish", "ru": "Самопроверка"}),
]
ICONS = os.path.join(ROOT, "libreoffice", "extension", "icons")


def titles(t, indent):
    return (indent + '<prop oor:name="Title" oor:type="xs:string">'
            + "".join('<value xml:lang="%s">%s</value>' % (lang, text) for lang, text in t.items()) + "</prop>\n")


def addons(url):
    """Addons.xcu for both editions: menu Tools ▸ UzTranslit, the toolbar, the icons. url(function) is the macro."""
    menu, bar, images = [], [], []
    for i, entry in enumerate(MENU):
        if entry is None:
            menu.append('          <node oor:name="m%02d" oor:op="replace">\n'
                        '            <prop oor:name="URL" oor:type="xs:string"><value>private:separator</value></prop>\n'
                        '          </node>' % i)
            continue
        func, icon, t = entry
        item = ('            <prop oor:name="URL" oor:type="xs:string"><value>%s</value></prop>\n' % url(func)
                + titles(t, "            ")
                + '            <prop oor:name="Target" oor:type="xs:string"><value>_self</value></prop>\n'
                + '            <prop oor:name="Context" oor:type="xs:string"><value>%s</value></prop>\n' % CONTEXT)
        menu.append('          <node oor:name="m%02d" oor:op="replace">\n%s          </node>' % (i, item))
        if icon:
            bar.append('        <node oor:name="t%02d" oor:op="replace">\n%s        </node>' % (i, item.replace("\n            ", "\n          ")[2:]))
            images.append('      <node oor:name="%s.image.%s" oor:op="replace">\n'
                          '        <prop oor:name="URL" oor:type="xs:string"><value>%s</value></prop>\n'
                          '        <node oor:name="UserDefinedImages">\n'
                          '          <prop oor:name="ImageSmallURL" oor:type="xs:string"><value>%%origin%%/icons/%s_16.png</value></prop>\n'
                          '          <prop oor:name="ImageBigURL" oor:type="xs:string"><value>%%origin%%/icons/%s_26.png</value></prop>\n'
                          '        </node>\n'
                          '      </node>' % (IDENT, func, url(func), icon, icon))
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
            '    <node oor:name="OfficeToolBar">\n'
            '      <node oor:name="%s.toolbar" oor:op="replace">\n%s\n      </node>\n'
            '    </node>\n'
            '    <node oor:name="Images">\n%s\n    </node>\n'
            '  </node>\n'
            '</oor:component-data>\n') % (IDENT, "\n".join(menu), IDENT, "\n".join(bar), "\n".join(images))


SETTINGS = [("Ascii", "false"), ("Dictionary", "true"), ("KeepHardSignAfterO", "false"), ("TsFinal", "true"), ("SkipUrls", "true")]


def settings_xcs():
    """/uz.jaybi.UzTranslit/Settings: what the Settings dialog edits and every run reads (both editions)."""
    return ('<?xml version="1.0" encoding="UTF-8"?>\n'
            '<oor:component-schema xmlns:oor="http://openoffice.org/2001/registry" xmlns:xs="http://www.w3.org/2001/XMLSchema" '
            'oor:name="UzTranslit" oor:package="uz.jaybi" xml:lang="en-US">\n'
            '  <templates/>\n'
            '  <component>\n'
            '    <group oor:name="Settings">\n'
            + "".join('      <prop oor:name="%s" oor:type="xs:boolean"><value>%s</value></prop>\n' % kv for kv in SETTINGS) +
            '    </group>\n'
            '  </component>\n'
            '</oor:component-schema>\n')


def add_common(z):
    z.writestr("UzTranslit.xcs", settings_xcs())
    for f in sorted(os.listdir(ICONS)):
        if f.endswith(".png"):
            with open(os.path.join(ICONS, f), "rb") as fh:
                z.writestr("icons/" + f, fh.read())


MANIFEST_COMMON = ('  <manifest:file-entry manifest:media-type="application/vnd.sun.star.configuration-schema" manifest:full-path="UzTranslit.xcs"/>\n'
                   '  <manifest:file-entry manifest:media-type="application/vnd.sun.star.configuration-data" manifest:full-path="Addons.xcu"/>\n')


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
            + MANIFEST_COMMON +
            '  <manifest:file-entry manifest:media-type="application/vnd.sun.star.framework-script" manifest:full-path="%s/"/>\n'
            '</manifest:manifest>\n') % SCRIPT_DIR


def build():
    core = open(CORE, encoding="utf-8").read()
    core = core.split('\nif __name__ == "__main__":')[0]  # drop the CLI entry point
    glue = open(GLUE, encoding="utf-8").read()
    script = core + "\n\n" + glue
    out = os.path.join(OUT_DIR, OXT_NAME)
    with Oxt(out) as z:
        z.writestr("META-INF/manifest.xml", manifest_xml())
        z.writestr("description.xml", description_xml())
        z.writestr("Addons.xcu", addons(script_url))
        add_common(z)
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
               "settings": "UzLO_Settings", "self_test": "UzSelfTest"}


XBA = ('<?xml version="1.0" encoding="UTF-8"?>\n'
       '<!DOCTYPE script:module PUBLIC "-//OpenOffice.org//DTD OfficeDocument 1.0//EN" "module.dtd">\n'
       '<script:module xmlns:script="http://openoffice.org/2000/script" script:name="%s" script:language="StarBasic">%s</script:module>\n')


def build_basic():
    basic_src = open(os.path.join(ROOT, "libreoffice", "UzTranslitLO.bas"), encoding="utf-8").read()
    esc = basic_src.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    out = os.path.join(OUT_DIR, OXT_BASIC)
    with Oxt(out) as z:
        z.writestr("META-INF/manifest.xml",
                   '<?xml version="1.0" encoding="UTF-8"?>\n'
                   '<manifest:manifest xmlns:manifest="http://openoffice.org/2001/manifest">\n'
                   + MANIFEST_COMMON +
                   '  <manifest:file-entry manifest:media-type="application/vnd.sun.star.basic-library" manifest:full-path="%s/"/>\n'
                   '</manifest:manifest>\n' % LIB)
        z.writestr("description.xml", description_xml().replace(IDENT + '"', IDENT + '"', 1))
        z.writestr("Addons.xcu", addons(lambda f: basic_url(BASIC_NAMES[f])))
        add_common(z)
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
                   "Menu and toolbar: Tools ▸ UzTranslit (settings there too). For Calc formulas such as =UZCONVERT(A1;\"lat\";\"new\") "
                   "import UzTranslitLO.bas into My Macros: LibreOffice does not call an extension's Basic functions from cells.\n"
                   "Web version: https://latin.jaybi.uz\n" % VERSION)
    print("built", out, os.path.getsize(out), "bytes")
    return out


if __name__ == "__main__":
    build()
    build_basic()
