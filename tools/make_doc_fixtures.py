#!/usr/bin/env python3
"""Generates the document fixtures for web/test/engine: Writer, Calc and Impress files in every format
LibreOffice can save (docx, odt, rtf, html, epub, xlsx, ods, csv, pptx, odp), built from small flat-ODF
sources that exercise the hard cases (a word split across bold/italic runs, footnotes, hyperlinks,
comments, header/footer, tables, tabs and line breaks).

usage: python3 tools/make_doc_fixtures.py        writes web/test/fixtures/docs/
LibreOffice runs headless with a throwaway profile in build/fixtures-profile.
"""
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "web" / "test" / "fixtures" / "docs"
PROFILE = ROOT / "build" / "fixtures-profile"

NS = ('xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" '
      'xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0" '
      'xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" '
      'xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0" '
      'xmlns:draw="urn:oasis:names:tc:opendocument:xmlns:drawing:1.0" '
      'xmlns:presentation="urn:oasis:names:tc:opendocument:xmlns:presentation:1.0" '
      'xmlns:svg="urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0" '
      'xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0" '
      'xmlns:xlink="http://www.w3.org/1999/xlink" xmlns:dc="http://purl.org/dc/elements/1.1/" '
      'xmlns:meta="urn:oasis:names:tc:opendocument:xmlns:meta:1.0" '
      'xmlns:of="urn:oasis:names:tc:opendocument:xmlns:of:1.2"')

LANG = '<style:text-properties fo:language="uz" fo:country="UZ" style:rfc-language-tag="uz-Cyrl-UZ" fo:script="Cyrl"/>'

WRITER = f'''<?xml version="1.0" encoding="UTF-8"?>
<office:document {NS} office:version="1.3" office:mimetype="application/vnd.oasis.opendocument.text">
 <office:meta><dc:title>Ўзбекистон ҳақида</dc:title></office:meta>
 <office:styles>
  <style:default-style style:family="paragraph">{LANG}</style:default-style>
  <style:style style:name="Standard" style:family="paragraph" style:class="text"/>
  <style:style style:name="Heading_20_1" style:display-name="Heading 1" style:family="paragraph" style:default-outline-level="1"><style:text-properties fo:font-size="18pt" fo:font-weight="bold"/></style:style>
 </office:styles>
 <office:automatic-styles>
  <style:style style:name="T1" style:family="text"><style:text-properties fo:font-weight="bold"/></style:style>
  <style:style style:name="T2" style:family="text"><style:text-properties fo:font-style="italic"/></style:style>
  <style:page-layout style:name="pm1"><style:page-layout-properties fo:page-width="21cm" fo:page-height="29.7cm"/><style:header-style/><style:footer-style/></style:page-layout>
 </office:automatic-styles>
 <office:master-styles>
  <style:master-page style:name="Standard" style:page-layout-name="pm1">
   <style:header><text:p text:style-name="Standard">Сарлавҳа: Тошкент</text:p></style:header>
   <style:footer><text:p text:style-name="Standard">Саҳифа охири</text:p></style:footer>
  </style:master-page>
 </office:master-styles>
 <office:body><office:text>
  <text:h text:style-name="Heading_20_1" text:outline-level="1">Ўзбекистон Республикаси</text:h>
  <text:p text:style-name="Standard"><text:span text:style-name="T1">ШАҲ</text:span>АР МАРКАЗИ ва <text:span text:style-name="T2">Тош</text:span>кент шаҳри.</text:p>
  <text:p text:style-name="Standard">Объект, компьютер ва цирк; Исҳоқ мўъжиза кўрди.<text:note text:id="ftn1" text:note-class="footnote"><text:note-citation>1</text:note-citation><text:note-body><text:p text:style-name="Standard">Изоҳ: ғалаба ва чироқ.</text:p></text:note-body></text:note></text:p>
  <text:p text:style-name="Standard">Сайт: <text:a xlink:type="simple" xlink:href="https://latin.jaybi.uz/">https://latin.jaybi.uz</text:a> — манзил<text:tab/>ва<text:line-break/>янги қатор.</text:p>
  <table:table table:name="Table1">
   <table:table-column table:number-columns-repeated="2"/>
   <table:table-row><table:table-cell office:value-type="string"><text:p text:style-name="Standard">Шаҳар</text:p></table:table-cell><table:table-cell office:value-type="string"><text:p text:style-name="Standard">Аҳоли</text:p></table:table-cell></table:table-row>
   <table:table-row><table:table-cell office:value-type="string"><text:p text:style-name="Standard">Самарқанд</text:p></table:table-cell><table:table-cell office:value-type="string"><text:p text:style-name="Standard">551 700</text:p></table:table-cell></table:table-row>
  </table:table>
  <text:p text:style-name="Standard"><office:annotation><dc:creator>Муаллиф</dc:creator><dc:date>2026-10-24T10:00:00</dc:date><text:p>Шарҳ: яхши.</text:p></office:annotation>Ёз фасли келди. ЕР юзи, Ер шари.</text:p>
 </office:text></office:body>
</office:document>
'''

CALC = f'''<?xml version="1.0" encoding="UTF-8"?>
<office:document {NS} office:version="1.3" office:mimetype="application/vnd.oasis.opendocument.spreadsheet">
 <office:styles><style:default-style style:family="table-cell">{LANG}</style:default-style></office:styles>
 <office:automatic-styles><style:style style:name="T1" style:family="text"><style:text-properties fo:font-weight="bold"/></style:style></office:automatic-styles>
 <office:body><office:spreadsheet>
  <table:table table:name="Sheet1">
   <table:table-row>
    <table:table-cell office:value-type="string"><text:p>Шаҳар</text:p></table:table-cell>
    <table:table-cell office:value-type="string"><text:p>Изоҳ</text:p></table:table-cell>
    <table:table-cell office:value-type="float" office:value="1500"><text:p>1500</text:p></table:table-cell>
   </table:table-row>
   <table:table-row>
    <table:table-cell office:value-type="string"><text:p><text:span text:style-name="T1">ТОШ</text:span>КЕНТ</text:p></table:table-cell>
    <table:table-cell office:value-type="string"><text:p>Пойтахт, марказ</text:p></table:table-cell>
    <table:table-cell table:formula="of:=[.C1]*2" office:value-type="float" office:value="3000"><text:p>3000</text:p></table:table-cell>
   </table:table-row>
   <table:table-row>
    <table:table-cell office:value-type="string"><text:p>Самарқанд</text:p></table:table-cell>
    <table:table-cell office:value-type="string"><text:p>Регистон</text:p><office:annotation><dc:creator>Али</dc:creator><text:p>Ғалаба</text:p></office:annotation></table:table-cell>
    <table:table-cell office:value-type="float" office:value="1.5E-3"><text:p>0.0015</text:p></table:table-cell>
   </table:table-row>
  </table:table>
 </office:spreadsheet></office:body>
</office:document>
'''

IMPRESS = f'''<?xml version="1.0" encoding="UTF-8"?>
<office:document {NS} office:version="1.3" office:mimetype="application/vnd.oasis.opendocument.presentation">
 <office:styles><style:default-style style:family="graphic">{LANG}</style:default-style></office:styles>
 <office:automatic-styles>
  <style:page-layout style:name="PM1"><style:page-layout-properties fo:page-width="28cm" fo:page-height="15.75cm"/></style:page-layout>
  <style:style style:name="T1" style:family="text"><style:text-properties fo:font-weight="bold"/></style:style>
 </office:automatic-styles>
 <office:master-styles><style:master-page style:name="Default" style:page-layout-name="PM1"/></office:master-styles>
 <office:body><office:presentation>
  <draw:page draw:name="page1" draw:master-page-name="Default">
   <draw:frame svg:x="2cm" svg:y="1cm" svg:width="24cm" svg:height="3cm"><draw:text-box><text:p>Ўзбекистон <text:span text:style-name="T1">ШАҲ</text:span>АРЛАРИ</text:p></draw:text-box></draw:frame>
   <draw:frame svg:x="2cm" svg:y="5cm" svg:width="24cm" svg:height="8cm"><draw:text-box><text:p>Тошкент — пойтахт.</text:p><text:p>Самарқанд ва Бухоро, мўъжиза.</text:p></draw:text-box></draw:frame>
   <presentation:notes><draw:frame presentation:class="notes" svg:x="2cm" svg:y="2cm" svg:width="17cm" svg:height="12cm"><draw:text-box><text:p>Маърузачи учун изоҳ.</text:p></draw:text-box></draw:frame></presentation:notes>
  </draw:page>
 </office:presentation></office:body>
</office:document>
'''

TARGETS = {
    "writer.fodt": [("docx", "docx:MS Word 2007 XML"), ("odt", "odt"), ("rtf", "rtf"),
                    ("html", "html:XHTML Writer File:UTF8"), ("epub", "epub")],
    "calc.fods": [("xlsx", "xlsx:Calc MS Excel 2007 XML"), ("ods", "ods")],
    "impress.fodp": [("pptx", "pptx:Impress MS PowerPoint 2007 XML"), ("odp", "odp")],
}


def soffice(args, cwd):
    cmd = ["soffice", "-env:UserInstallation=" + PROFILE.resolve().as_uri(), "--headless", "--norestore"] + args
    subprocess.run(cmd, cwd=cwd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=300)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        for name, src in (("writer.fodt", WRITER), ("calc.fods", CALC), ("impress.fodp", IMPRESS)):
            (Path(tmp) / name).write_text(src, encoding="utf-8")
            shutil.copy(Path(tmp) / name, OUT / name)
            for ext, flt in TARGETS[name]:
                soffice(["--convert-to", flt, "--outdir", tmp, name], tmp)
                produced = Path(tmp) / (Path(name).stem + "." + ext)
                shutil.copy(produced, OUT / produced.name)
                print("wrote", (OUT / produced.name).relative_to(ROOT))


if __name__ == "__main__":
    main()
