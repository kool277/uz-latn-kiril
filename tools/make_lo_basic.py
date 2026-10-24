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
    """UTF-16 code units in hex, the way Basic's ChrW() takes them (an emoji is two units)."""
    b = s.encode("utf-16-le", "surrogatepass")
    return " ".join("%04X" % (b[i] | b[i + 1] << 8) for i in range(0, len(b), 2))


def build_test_module(out_dir, result_path):
    fx = json.load(open(os.path.join(ROOT, "spec", "fixtures.json"), encoding="utf-8"))
    lines = ["Option Explicit", "Option VBASupport 1", "",
             "Private okN As Long, badN As Long, logS As String", "",
             "Private Function UX(ByVal h As String) As String",
             "    Dim i As Long, o As String, tok As String, v As Long",
             "    h = Trim(h) & \" \"",
             "    For i = 1 To Len(h)",
             "        If Mid(h, i, 1) = \" \" Then",
             "            If Len(tok) > 0 Then",
             "                v = CLng(\"&H\" & tok)",
             "                If v < 0 Then v = v + 65536",  # &H8000-&HFFFF parse as negative 16-bit integers
             "                o = o & ChrW(v): tok = \"\"",
             "            End If",
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
              '    RunDiff',
              '    RunSplit',
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
    # differential corpus (tools/make_differential.mjs), read at run time: too large to inline in a module
    tsv = write_differential_tsv(out_dir)
    lines += ["Private Sub RunDiff",
              "    Dim f As Integer, ln As String, p() As String, got As String, okD As Long, badD As Long, logD As String",
              '    If Dir("%s") = "" Then Exit Sub' % tsv,
              "    f = FreeFile",
              '    Open "%s" For Input As #f' % tsv,
              "    Do While Not EOF(f)",
              "        Line Input #f, ln",
              "        p = Split(ln, Chr(9))",
              '        If p(0) = "detect" Then',
              "            On Error Resume Next",
              "            got = UzDetect(UX(p(3)))",
              "            If Err <> 0 Then got = \"BASIC ERROR \" & Err & \": \" & Error$: Err.Clear",
              "            On Error GoTo 0",
              "            If got = p(4) Then",
              "                okD = okD + 1",
              "            Else",
              "                badD = badD + 1",
              '                If badD <= 20 Then logD = logD & "DIFF detect " & p(3) & " want=" & p(4) & " got=" & got & Chr(10)',
              "            End If",
              "        Else",
              '            UzOptAscii = (Mid(p(2), 1, 1) = "1")',
              '            UzOptKeepHardSignAfterO = (Mid(p(2), 2, 1) = "1")',
              '            UzOptNoTsFinal = (Mid(p(2), 3, 1) = "1")',
              '            UzOptNoDictionary = (Mid(p(2), 4, 1) = "1")',
              '            UzOptNoSkipUrls = (Mid(p(2), 5, 1) = "1")',
              "            On Error Resume Next",
              "            got = UzConvert(UX(p(3)), p(0), p(1))",
              "            If Err <> 0 Then got = \"BASIC ERROR \" & Err & \": \" & Error$: Err.Clear",
              "            On Error GoTo 0",
              "            If got = UX(p(4)) Then",
              "                okD = okD + 1",
              "            Else",
              "                badD = badD + 1",
              '                If badD <= 20 Then logD = logD & "DIFF " & p(0) & "->" & p(1) & " " & p(2) & " in=" & p(3) & " want=" & UX(p(4)) & " got=" & got & Chr(10)',
              "            End If",
              "        End If",
              "    Loop",
              "    Close #f",
              "    UzOptAscii = False: UzOptKeepHardSignAfterO = False: UzOptNoTsFinal = False: UzOptNoDictionary = False: UzOptNoSkipUrls = False",
              "    f = FreeFile",
              '    Open "%s" For Append As #f' % result_path,
              '    Print #f, okD & " passed, " & badD & " failed (differential vs core/js)"',
              "    Print #f, logD",
              "    Close #f",
              "End Sub", ""]
    split = write_split_tsv(out_dir)
    lines += ["Private Sub RunSplit",
              "    Dim f As Integer, ln As String, p() As String, a() As String, w() As String, pieces() As String, outs() As String",
              "    Dim i As Long, n As Long, okS As Long, badS As Long, logX As String, good As Boolean, why As String",
              '    If Dir("%s") = "" Then Exit Sub' % split,
              "    f = FreeFile",
              '    Open "%s" For Input As #f' % split,
              "    Do While Not EOF(f)",
              "        Line Input #f, ln",
              "        p = Split(ln, Chr(9))",
              '        a = Split(p(3), "|"): w = Split(p(4), "|")',
              "        n = UBound(a) + 1",
              "        ReDim pieces(1 To n)",
              "        For i = 1 To n",
              "            pieces(i) = UX(a(i - 1))",
              "        Next",
              '        UzOptAscii = (Mid(p(2), 1, 1) = "1")',
              '        UzOptKeepHardSignAfterO = (Mid(p(2), 2, 1) = "1")',
              '        UzOptNoTsFinal = (Mid(p(2), 3, 1) = "1")',
              '        UzOptNoDictionary = (Mid(p(2), 4, 1) = "1")',
              '        UzOptNoSkipUrls = (Mid(p(2), 5, 1) = "1")',
              '        why = ""',
              "        On Error Resume Next",
              "        UzSplitConvert pieces, outs, 1, n, p(0), p(1)",
              '        If Err <> 0 Then why = "BASIC ERROR " & Err & ": " & Error$: Err.Clear',
              "        On Error GoTo 0",
              '        If why = "" Then',
              "            For i = 1 To n",
              '                If outs(i) <> UX(w(i - 1)) Then why = "piece " & i & " got " & outs(i) & " want " & UX(w(i - 1)): Exit For',
              "            Next",
              "        End If",
              '        If why = "" Then',
              "            okS = okS + 1",
              "        Else",
              "            badS = badS + 1",
              '            If badS <= 20 Then logX = logX & "SPLIT " & p(0) & "->" & p(1) & " " & p(2) & " " & p(3) & ": " & why & Chr(10)',
              "        End If",
              "    Loop",
              "    Close #f",
              "    UzOptAscii = False: UzOptKeepHardSignAfterO = False: UzOptNoTsFinal = False: UzOptNoDictionary = False: UzOptNoSkipUrls = False",
              "    f = FreeFile",
              '    Open "%s" For Append As #f' % result_path,
              '    Print #f, okS & " passed, " & badS & " failed (UzSplitConvert vs the prefix-by-prefix split)"',
              "    Print #f, logX",
              "    Close #f",
              "End Sub", ""]
    os.makedirs(out_dir, exist_ok=True)
    p = os.path.join(out_dir, "UzTest.bas")
    open(p, "w", encoding="utf-8").write("\n".join(lines))
    print("wrote", p, "with", sum(len(c) for c in chunks), "checks")
    return p


def write_differential_tsv(out_dir):
    """build/differential.json → TSV for the Basic runner: the cases the VBA options can express (marks either ʻ/ʼ
    or ASCII). Columns: from, to, flags (ascii keepHardSign noTsFinal noDictionary noSkipUrls), input, output."""
    path = os.path.join(out_dir, "differential.tsv")
    src = os.path.join(ROOT, "build", "differential.json")
    if os.path.exists(path):
        os.remove(path)
    if not os.path.exists(src):
        return path
    d = json.load(open(src, encoding="utf-8"))
    rows = []
    for c in d["cases"]:
        o = c["options"]
        marks = (o["okina"], o["tutuq"])
        if marks not in (("\u02bb", "\u02bc"), ("'", "'")):
            continue
        flags = "".join("1" if v else "0" for v in (marks == ("'", "'"), not o["dropHardSignAfterO"], not o["tsFinal"],
                                                     not o["dictionary"], not o["skipUrls"]))
        rows.append("\t".join((c["from"], c["to"], flags, hx(c["in"]), hx(c["out"]))))
    # Basic runs ~30 cases a second: a few thousand keep the suite at about two minutes
    rows = rows[:int(os.environ.get("UZT_LO_DIFF_CASES", 3000))]
    rows += ["\t".join(("detect", "", "", hx(x["in"]), x["expect"])) for x in d["detect"][:500]]
    os.makedirs(out_dir, exist_ok=True)
    with open(path, "w", encoding="ascii", newline="\n") as f:
        f.write("\n".join(rows) + "\n")
    return path


def naive_split(texts, f, t, options):
    """The definition UzSplitConvert implements in linear time: each cut where the conversion of all text before it ends."""
    import uztranslit
    src = "".join(texts)
    out = uztranslit.convert(src, f, t, options)
    if out == src:
        return list(texts)
    pieces, prev, b = [], 0, 0
    for i, s in enumerate(texts):
        b += len(s)
        cur = len(out) if i == len(texts) - 1 else min(len(uztranslit.convert(src[:b], f, t, options)), len(out))
        cur = max(cur, prev)
        pieces.append(out[prev:cur])
        prev = cur
    return pieces


def write_split_tsv(out_dir):
    """Differential cases cut into random runs, with the pieces the prefix-by-prefix split gives (Python core).
    Columns: from, to, flags, input pieces, output pieces (hex, pieces separated by |)."""
    import random
    sys.path.insert(0, os.path.join(ROOT, "core", "python"))
    path = os.path.join(out_dir, "split.tsv")
    src = os.path.join(ROOT, "build", "differential.json")
    if os.path.exists(path):
        os.remove(path)
    if not os.path.exists(src):
        return path
    d = json.load(open(src, encoding="utf-8"))
    rng = random.Random(20261024)
    rows = []
    for c in d["cases"]:
        o = c["options"]
        marks = (o["okina"], o["tutuq"])
        if c["from"] == "auto" or marks not in (("\u02bb", "\u02bc"), ("'", "'")):
            continue
        text, texts, i = c["in"], [], 0
        while i < len(text):
            k = rng.randint(1, 8)
            texts.append(text[i:i + k])
            i += k
        flags = "".join("1" if v else "0" for v in (marks == ("'", "'"), not o["dropHardSignAfterO"], not o["tsFinal"],
                                                     not o["dictionary"], not o["skipUrls"]))
        want = naive_split(texts, c["from"], c["to"], o)
        rows.append("\t".join((c["from"], c["to"], flags, "|".join(hx(x) for x in texts), "|".join(hx(x) for x in want))))
        if len(rows) >= int(os.environ.get("UZT_LO_SPLIT_CASES", 80)):
            break
    os.makedirs(out_dir, exist_ok=True)
    with open(path, "w", encoding="ascii", newline="\n") as f:
        f.write("\n".join(rows) + "\n")
    return path


def office_library():
    """The MS-Office modules (document macros and ribbon callbacks included) as a library of their own, plus a module
    whose Run compiles them: LibreOffice's VBA mode catches syntax errors in macros that only Office can run."""
    src = open(VBA, encoding="utf-8").read()
    src = re.sub(r"^Attribute VB_Name.*\n", "", src)
    src = src.replace("Option Explicit\n", "Option Explicit\nOption VBASupport 1\n", 1)
    check = "\n".join(["Option Explicit", "Option VBASupport 1", "",
                       "Sub Run",
                       "    Dim f As Integer, s As String",
                       '    s = UzConvert("Shahar", "lat", "cyr")',
                       '    If False Then UzRibbon_OnAction Nothing    \' compiles the ribbon module too',
                       "    f = FreeFile",
                       '    Open "%s" For Output As #f' % os.path.join(ROOT, "build", "lo-test", "office.txt"),
                       '    Print #f, "office module compiled: " & s',
                       '    Print #f, "UzSelfTest: " & UzSelfTestResult()',
                       "    Close #f",
                       "End Sub", ""])
    ribbon = open(os.path.join(ROOT, "office-vba", "UzTranslitRibbon.bas"), encoding="utf-8").read()
    ribbon = re.sub(r"^Attribute VB_Name.*\n", "", ribbon).replace("Option Explicit\n", "Option Explicit\nOption VBASupport 1\n", 1)
    return {"UzTranslit": src, "UzTranslitRibbon": ribbon, "UzCheck": check}


XBA = ('<?xml version="1.0" encoding="UTF-8"?>\n'
       '<!DOCTYPE script:module PUBLIC "-//OpenOffice.org//DTD OfficeDocument 1.0//EN" "module.dtd">\n'
       '<script:module xmlns:script="http://openoffice.org/2000/script" script:name="%s" script:language="StarBasic">%s</script:module>\n')


def esc(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def install_into_profile(profile_basic_dir, libs):
    """libs: {library: {module: source}}. Writes these libraries into a LibreOffice user profile's basic folder."""
    entries = "".join(' <library:library library:name="%s" xlink:href="$(USER)/basic/%s/%s.xlb/" xlink:type="simple" library:link="false"/>\n'
                      % (lib, lib, "%s") for lib in libs)
    for kind in ("script", "dialog"):
        with open(os.path.join(profile_basic_dir, kind + ".xlc"), "w", encoding="utf-8") as f:
            f.write('<?xml version="1.0" encoding="UTF-8"?>\n'
                    '<!DOCTYPE library:libraries PUBLIC "-//OpenOffice.org//DTD OfficeDocument 1.0//EN" "libraries.dtd">\n'
                    '<library:libraries xmlns:library="http://openoffice.org/2000/library" xmlns:xlink="http://www.w3.org/1999/xlink">\n'
                    + entries.replace("%s", kind) +
                    '</library:libraries>\n')
    for lib, modules in libs.items():
        d = os.path.join(profile_basic_dir, lib)
        os.makedirs(d, exist_ok=True)
        for old in os.listdir(d):
            if old.endswith(".xba"):
                os.remove(os.path.join(d, old))
        with open(os.path.join(d, "script.xlb"), "w", encoding="utf-8") as f:
            f.write('<?xml version="1.0" encoding="UTF-8"?>\n'
                    '<!DOCTYPE library:library PUBLIC "-//OpenOffice.org//DTD OfficeDocument 1.0//EN" "library.dtd">\n'
                    '<library:library xmlns:library="http://openoffice.org/2000/library" library:name="%s" library:readonly="false" library:passwordprotected="false">\n' % lib
                    + "".join(' <library:element library:name="%s"/>\n' % m for m in modules) +
                    '</library:library>\n')
        with open(os.path.join(d, "dialog.xlb"), "w", encoding="utf-8") as f:
            f.write('<?xml version="1.0" encoding="UTF-8"?>\n'
                    '<!DOCTYPE library:library PUBLIC "-//OpenOffice.org//DTD OfficeDocument 1.0//EN" "library.dtd">\n'
                    '<library:library xmlns:library="http://openoffice.org/2000/library" library:name="%s" library:readonly="false" library:passwordprotected="false"/>\n' % lib)
        for name, src in modules.items():
            with open(os.path.join(d, name + ".xba"), "w", encoding="utf-8") as f:
                f.write(XBA % (name, esc(src)))
        print("installed", lib, list(modules), "into", d)


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
            "Standard": {"UzTranslitLO": open(OUT, encoding="utf-8").read(), "UzTest": open(test_path, encoding="utf-8").read()},
            "UzOffice": office_library(),
        })
        print("now run:  python3 tools/lo_run_macro.py Standard.UzTest.RunAll", result)
        print("     and  python3 tools/lo_run_macro.py UzOffice.UzCheck.Run", os.path.join(out_dir, "office.txt"))
