#!/usr/bin/env python3
"""
Builds libreoffice/UzTranslitLO.bas from office-vba/UzTranslit.bas (shared engine) + libreoffice/UzTranslitLO_ui.bas,
and (optionally) a fixture-driven test module so the Basic engine can be verified headlessly:

    python3 tools/make_lo_basic.py            # regenerate UzTranslitLO.bas
    python3 tools/make_lo_basic.py --test     # also write build/lo-test/UzTest.bas + install it into the
                                              # throwaway profile build/lo-test/profile (see tools/lo_run_macro.py)
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VBA = os.path.join(ROOT, "office-vba", "UzTranslit.bas")
UI = os.path.join(ROOT, "libreoffice", "UzTranslitLO_ui.bas")
OUT = os.path.join(ROOT, "libreoffice", "UzTranslitLO.bas")


def engine_from_vba():
    src = open(VBA, encoding="utf-8").read()
    # drop the VBE-only attribute line
    src = re.sub(r"^Attribute VB_Name.*\n", "", src)
    # cut the MS-Office document-macro section (from its banner up to the ENGINE banner)
    start = src.index("'  DOCUMENT MACROS")
    start = src.rfind("' ====", 0, start)
    end = src.index("'  ENGINE")
    end = src.rfind("' ====", 0, end)
    src = src[:start] + src[end:]
    header = ("' ===== Generated from office-vba/UzTranslit.bas by tools/make_lo_basic.py — do not edit the engine here =====\n"
              "Option Explicit\nOption VBASupport 1\n")
    src = src.replace("Option Explicit\nOption Compare Binary\n", header, 1)
    return src


def build():
    engine = engine_from_vba()
    ui = open(UI, encoding="utf-8").read()
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(engine.rstrip() + "\n\n" + ui)
    print("wrote", OUT, len(engine.splitlines()) + len(ui.splitlines()), "lines")
    return engine


def hx(s):
    return " ".join("%04X" % ord(c) for c in s)


def build_test_module(out_dir, result_path):
    fx = json.load(open(os.path.join(ROOT, "spec", "fixtures.json"), encoding="utf-8"))
    lines = ["Option Explicit", "Option VBASupport 1", "",
             "Private okN As Long, badN As Long, logS As String", "",
             "Private Function UX(ByVal h As String) As String",
             "    Dim i As Long, o As String, tok As String",
             "    h = Trim(h) & \" \"",
             "    For i = 1 To Len(h)",
             "        If Mid(h, i, 1) = \" \" Then",
             "            If Len(tok) > 0 Then o = o & ChrW(CLng(\"&H\" & tok)): tok = \"\"",
             "        Else",
             "            tok = tok & Mid(h, i, 1)",
             "        End If",
             "    Next",
             "    UX = o",
             "End Function", "",
             "Private Sub Chk(ByVal id As String, ByVal got As String, ByVal want As String)",
             "    If got = want Then",
             "        okN = okN + 1",
             "    Else",
             "        badN = badN + 1",
             "        logS = logS & \"FAIL \" & id & \" want=\" & want & \" got=\" & got & Chr(10)",
             "    End If",
             "End Sub", "",
             "Sub RunAll",
             "    Dim ef As Integer",
             "    On Error GoTo ErrH"]
    # split into several subs to stay under Basic's per-procedure limits
    chunks = []
    cur = []
    for c in fx["cases"]:
        cur.append('    Chk "%s", UzConvert(UX("%s"), "%s", "%s"), UX("%s")' % (c["id"], hx(c["in"]), c["from"], c["to"], hx(c["out"])))
        if len(cur) >= 60:
            chunks.append(cur); cur = []
    for r in fx["roundtrips"]:
        cur.append('    Chk "%s", UzConvert(UzConvert(UX("%s"), "%s", "%s"), "%s", "%s"), UX("%s")' % (
            r["id"], hx(r["in"]), r["from"], r["via"], r["via"], r["from"], hx(r["in"])))
    for d in fx["detect"]:
        cur.append('    Chk "detect %s", UzDetect(UX("%s")), "%s"' % (hx(d["in"])[:20], hx(d["in"]), d["expect"]))
    for o in fx["optional"]:
        if o["feature"] == "asciiApostrophe":
            cur.append('    UzOptAscii = True')
            cur.append('    Chk "optional/ascii", UzConvert(UX("%s"), "%s", "%s"), UX("%s")' % (hx(o["in"]), o["from"], o["to"], hx(o["out"])))
            cur.append('    UzOptAscii = False')
    chunks.append(cur)
    for i in range(len(chunks)):
        lines.append("    Part%d" % i)
    lines += ['    Dim f As Integer',
              '    f = FreeFile',
              '    Open "%s" For Output As #f' % result_path,
              '    Print #f, okN & " passed, " & badN & " failed (UzTranslitLO.bas via LibreOffice Basic)"',
              '    Print #f, logS',
              '    Close #f',
              '    Exit Sub',
              'ErrH:',
              '    ef = FreeFile',
              '    Open "%s" For Output As #ef' % result_path,
              '    Print #ef, "BASIC ERROR " & Err & ": " & Error$ & " (line " & Erl & ") after " & okN & " ok / " & badN & " bad"',
              '    Print #ef, logS',
              '    Close #ef',
              "End Sub", ""]
    for i, ch in enumerate(chunks):
        lines.append("Private Sub Part%d" % i)
        lines += ch
        lines.append("End Sub")
        lines.append("")
    os.makedirs(out_dir, exist_ok=True)
    p = os.path.join(out_dir, "UzTest.bas")
    open(p, "w", encoding="utf-8").write("\n".join(lines))
    print("wrote", p, "with", sum(len(c) for c in chunks), "checks")
    return p


XBA = ('<?xml version="1.0" encoding="UTF-8"?>\n'
       '<!DOCTYPE script:module PUBLIC "-//OpenOffice.org//DTD OfficeDocument 1.0//EN" "module.dtd">\n'
       '<script:module xmlns:script="http://openoffice.org/2000/script" script:name="%s" script:language="StarBasic">%s</script:module>\n')


def esc(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def install_into_profile(profile_basic_dir, modules):
    """modules: {name: source}. Writes the Standard library of a LibreOffice user profile."""
    std = os.path.join(profile_basic_dir, "Standard")
    os.makedirs(std, exist_ok=True)
    with open(os.path.join(profile_basic_dir, "script.xlc"), "w", encoding="utf-8") as f:
        f.write('<?xml version="1.0" encoding="UTF-8"?>\n'
                '<!DOCTYPE library:libraries PUBLIC "-//OpenOffice.org//DTD OfficeDocument 1.0//EN" "libraries.dtd">\n'
                '<library:libraries xmlns:library="http://openoffice.org/2000/library" xmlns:xlink="http://www.w3.org/1999/xlink">\n'
                ' <library:library library:name="Standard" xlink:href="$(USER)/basic/Standard/script.xlb/" xlink:type="simple" library:link="false"/>\n'
                '</library:libraries>\n')
    with open(os.path.join(profile_basic_dir, "dialog.xlc"), "w", encoding="utf-8") as f:
        f.write('<?xml version="1.0" encoding="UTF-8"?>\n'
                '<!DOCTYPE library:libraries PUBLIC "-//OpenOffice.org//DTD OfficeDocument 1.0//EN" "libraries.dtd">\n'
                '<library:libraries xmlns:library="http://openoffice.org/2000/library" xmlns:xlink="http://www.w3.org/1999/xlink">\n'
                ' <library:library library:name="Standard" xlink:href="$(USER)/basic/Standard/dialog.xlb/" xlink:type="simple" library:link="false"/>\n'
                '</library:libraries>\n')
    with open(os.path.join(std, "script.xlb"), "w", encoding="utf-8") as f:
        f.write('<?xml version="1.0" encoding="UTF-8"?>\n'
                '<!DOCTYPE library:library PUBLIC "-//OpenOffice.org//DTD OfficeDocument 1.0//EN" "library.dtd">\n'
                '<library:library xmlns:library="http://openoffice.org/2000/library" library:name="Standard" library:readonly="false" library:passwordprotected="false">\n'
                + "".join(' <library:element library:name="%s"/>\n' % m for m in modules) +
                '</library:library>\n')
    with open(os.path.join(std, "dialog.xlb"), "w", encoding="utf-8") as f:
        f.write('<?xml version="1.0" encoding="UTF-8"?>\n'
                '<!DOCTYPE library:library PUBLIC "-//OpenOffice.org//DTD OfficeDocument 1.0//EN" "library.dtd">\n'
                '<library:library xmlns:library="http://openoffice.org/2000/library" library:name="Standard" library:readonly="false" library:passwordprotected="false"/>\n')
    for name, src in modules.items():
        with open(os.path.join(std, name + ".xba"), "w", encoding="utf-8") as f:
            f.write(XBA % (name, esc(src)))
    print("installed modules", list(modules), "into", std)


if __name__ == "__main__":
    engine = build()
    if "--test" in sys.argv:
        out_dir = os.path.join(ROOT, "build", "lo-test")
        result = os.path.join(out_dir, "result.txt")
        test_path = build_test_module(out_dir, result)
        # never the developer's own profile: that would replace their My Macros ▸ Standard library
        profile = os.environ.get("LO_PROFILE_BASIC")
        if not profile:
            install_dir = os.path.join(out_dir, "profile")
            if not os.path.exists(os.path.join(install_dir, "user", "registrymodifications.xcu")):
                # a fresh profile resets basic/script.xlc on first start, so let soffice create it first
                import subprocess
                from pathlib import Path
                subprocess.run(["soffice", "-env:UserInstallation=" + Path(install_dir).resolve().as_uri(),
                                "--headless", "--norestore", "--terminate_after_init"], check=True,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=120)
            profile = os.path.join(install_dir, "user", "basic")
        install_into_profile(profile, {
            "UzTranslitLO": open(OUT, encoding="utf-8").read(),
            "UzTest": open(test_path, encoding="utf-8").read(),
        })
        print("now run:  python3 tools/lo_run_macro.py Standard.UzTest.RunAll", result)
