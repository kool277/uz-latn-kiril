#!/usr/bin/env python3
"""End-to-end test of the LibreOffice extensions: installs an .oxt into a throwaway profile, builds Writer, Calc and
Impress documents through UNO, runs the menu macros headlessly and checks text and formatting.

usage: python3 tools/lo_extension_test.py [basic|python|all]     (default: all; python needs the Python script provider)
Needs soffice, unopkg and python3-uno. Exit code 1 on any failure.
"""
import os
import shutil
import subprocess
import sys
import time

import uno
from com.sun.star.beans import PropertyValue  # noqa: F401

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORK = os.path.join(ROOT, "build", "lo-ext-test")
BOLD, NORMAL = 150.0, 100.0
EDITIONS = {
    "basic": ("uztranslit-libreoffice.oxt",
              "vnd.sun.star.script:UzTranslit.UzTranslitLO.UzLO_%s?language=Basic&location=application",
              {"auto_to_lat": "AutoToLat", "lat_to_cyr": "LatToCyr", "auto_to_new": "AutoToNew", "cyr_to_lat": "CyrToLat",
               "settings_dialog": "SettingsDialog", "settings_save": "SettingsSave"}),
    "python": ("uztranslit-libreoffice-python.oxt",
               "vnd.sun.star.script:uztranslit-libreoffice-python.oxt|python|uztranslit_lo.py$%s?language=Python&location=user:uno_packages",
               {"auto_to_lat": "auto_to_lat", "lat_to_cyr": "lat_to_cyr", "auto_to_new": "auto_to_new", "cyr_to_lat": "cyr_to_lat",
                "settings_dialog": "settings_dialog", "settings_save": "settings_save"}),
}

failures = []


def check(name, got, want):
    if got == want:
        print("  ok   %s" % name)
    else:
        failures.append(name)
        print("  FAIL %s\n       want %r\n       got  %r" % (name, want, got))


def portions(par):
    """[(text, bold?)] of a paragraph."""
    out = []
    en = par.createEnumeration()
    while en.hasMoreElements():
        p = en.nextElement()
        try:
            kind = p.TextPortionType
        except Exception:
            kind = "Text"
        if kind == "Text" and p.getString():
            out.append((p.getString(), p.CharWeight > 100.0))
    return out


def paragraphs(xtext):
    out = []
    en = xtext.createEnumeration()
    while en.hasMoreElements():
        el = en.nextElement()
        if el.supportsService("com.sun.star.text.Paragraph"):
            out.append(el)
    return out


def add_runs(xtext, runs, cur=None):
    cur = cur or xtext.createTextCursor()
    for s, bold in runs:
        cur.setPropertyValue("CharWeight", BOLD if bold else NORMAL)
        xtext.insertString(cur, s, False)
    cur.setPropertyValue("CharWeight", NORMAL)
    return cur


def start_office(profile, port):
    env = dict(os.environ, UZT_QUIET="1")
    url = uno.systemPathToFileUrl(profile)
    proc = subprocess.Popen(["soffice", "-env:UserInstallation=" + url, "--headless", "--norestore", "--nologo", "--nodefault",
                             "--accept=socket,host=127.0.0.1,port=%d;urp;StarOffice.ComponentContext" % port],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, env=env)
    local = uno.getComponentContext()
    resolver = local.ServiceManager.createInstanceWithContext("com.sun.star.bridge.UnoUrlResolver", local)
    for _ in range(60):
        try:
            return proc, resolver.resolve("uno:socket,host=127.0.0.1,port=%d;urp;StarOffice.ComponentContext" % port)
        except Exception:
            time.sleep(1)
    proc.kill()
    raise RuntimeError("soffice did not start")


def run_macro(desktop, doc, url):
    frame = doc.CurrentController.Frame
    frame.activate()
    desktop.setActiveFrame(frame)
    doc.getScriptProvider().getScript(url).invoke((), (), ())


def writer_tests(desktop, macro):
    doc = desktop.loadComponentFromURL("private:factory/swriter", "_blank", 0, ())
    text = doc.getText()
    cur = add_runs(text, [("Ш", True), ("АҲАР маркази", False)])
    text.insertControlCharacter(cur, 0, False)
    add_runs(text, [("Ер юзи, ", False), ("Т", True), ("ер", False), (" ва кўча 😀 шаҳри", False)], cur)
    text.insertControlCharacter(cur, 0, False)
    add_runs(text, [("Изоҳ билан", False)], cur)
    note = doc.createInstance("com.sun.star.text.Footnote")
    text.insertTextContent(cur, note, False)
    note.setString("Шарҳ: ғалаба")
    ann = doc.createInstance("com.sun.star.text.textfield.Annotation")
    ann.Author = "Муаллиф"
    ann.Content = "Яхши"
    text.insertTextContent(cur, ann, False)
    text.insertControlCharacter(cur, 0, False)
    tbl = doc.createInstance("com.sun.star.text.TextTable")
    tbl.initialize(1, 2)
    text.insertTextContent(cur, tbl, False)
    tbl.getCellByName("A1").setString("Самарқанд")
    tbl.getCellByName("B1").setString("Бухоро")
    style = doc.getStyleFamilies().getByName("PageStyles").getByName("Standard")
    style.HeaderIsOn = True
    style.HeaderText.setString("Сарлавҳа")

    run_macro(desktop, doc, macro["auto_to_lat"])
    ps = paragraphs(text)
    check("writer: word split by bold keeps its casing", portions(ps[0]), [("SH", True), ("AHAR markazi", False)])
    # (equally formatted runs are one portion in Writer)
    check("writer: е after a bold letter", portions(ps[1]), [("Yer yuzi, ", False), ("T", True), ("er va koʻcha 😀 shahri", False)])
    check("writer: footnote", note.getString(), "Sharh: gʻalaba")
    check("writer: comment text", ann.Content, "Yaxshi")
    check("writer: comment author untouched", ann.Author, "Муаллиф")
    check("writer: table", (tbl.getCellByName("A1").getString(), tbl.getCellByName("B1").getString()), ("Samarqand", "Buxoro"))
    check("writer: header", style.HeaderText.getString(), "Sarlavha")
    doc.close(True)

    # a paragraph of 600 runs (text pasted from a PDF looks like this): the split must stay linear
    doc = desktop.loadComponentFromURL("private:factory/swriter", "_blank", 0, ())
    add_runs(doc.getText(), [("Ша", True), ("ҳар ", False)] * 300)
    t0 = time.time()
    run_macro(desktop, doc, macro["auto_to_lat"])
    took = time.time() - t0
    check("writer: 600 runs keep their formatting", portions(paragraphs(doc.getText())[0]), [("Sha", True), ("har ", False)] * 300)
    check("writer: 600 runs in under 20 s (%.1f s)" % took, took < 20, True)
    doc.close(True)

    # what the run must keep: links (one of a single letter), character styles, language; one undo step; tracking
    doc = desktop.loadComponentFromURL("private:factory/swriter", "_blank", 0, ())
    text = doc.getText()
    for s, props in (("Bosh ", {}), ("sahifa", {"HyperLinkURL": "https://example.uz/a"}), (" va ", {}),
                     ("u", {"HyperLinkURL": "https://example.uz/b"}), (" ", {}), ("shahar", {"CharStyleName": "Emphasis"}),
                     (" ", {}), ("yoz", {"CharLocale": uno.createUnoStruct("com.sun.star.lang.Locale", "uz", "UZ", "")})):
        cur = text.createTextCursorByRange(text.getEnd())
        text.insertString(cur, s, False)
        cur.goLeft(len(s), True)
        for k, v in props.items():
            cur.setPropertyValue(k, v)
    doc.RecordChanges = True
    before = text.getString()
    run_macro(desktop, doc, macro["lat_to_cyr"])
    pors = []
    en = paragraphs(text)[0].createEnumeration()
    while en.hasMoreElements():
        pors.append(en.nextElement())

    def prop(word, name):  # a property of the portion that starts with word
        hits = [getattr(p, name) for p in pors if p.getString().startswith(word)]
        return hits[0] if hits else "(no portion starts with %s)" % word
    check("writer: link text converted, address kept", prop("саҳифа", "HyperLinkURL"), "https://example.uz/a")
    check("writer: one-letter link keeps its address", prop("у", "HyperLinkURL"), "https://example.uz/b")
    check("writer: character style kept", prop("шаҳар", "CharStyleName"), "Emphasis")
    check("writer: language kept", getattr(prop("ёз", "CharLocale"), "Variant", None), "uz-Latn-UZ")  # (LibreOffice's form of uz-UZ)
    check("writer: no tracked changes from the run", doc.Redlines.getCount(), 0)
    check("writer: change tracking switched back on", doc.RecordChanges, True)
    um = doc.getUndoManager()
    check("writer: one undo step", um.getCurrentUndoActionTitle(), "UzTranslit")
    um.undo()
    check("writer: undo restores the text", text.getString(), before)
    doc.close(True)

    doc = desktop.loadComponentFromURL("private:factory/swriter", "_blank", 0, ())
    doc.getText().setString("Sayt: https://latin.jaybi.uz/test va mail@example.com, Shahar")
    run_macro(desktop, doc, macro["lat_to_cyr"])
    check("writer: URLs and e-mails stay", doc.getText().getString(), "Сайт: https://latin.jaybi.uz/test ва mail@example.com, Шаҳар")
    doc.close(True)


def startup_tests(desktop, macro, edition_name):
    """The menu, the toolbar and its icons are registered."""
    ui = config(desktop, "/org.openoffice.Office.Addons/AddonUI")
    menu = ui.getByName("OfficeMenuBar").getByName("uz.jaybi.uztranslit.menu").getByName("Submenu")
    titles = [menu.getByName(n).Title for n in menu.getElementNames() if menu.getByName(n).URL != "private:separator"]
    check("menu: 11 commands", len(titles), 11)
    bar = ui.getByName("OfficeToolBar").getByName("uz.jaybi.uztranslit.toolbar")
    check("toolbar: 4 buttons", len(bar.getElementNames()), 4)
    images = [n for n in ui.getByName("Images").getElementNames() if n.startswith("uz.jaybi.uztranslit.image.")]
    check("toolbar: 4 icons", len(images), 4)


def config(desktop, path, update=False):
    ctx = desktop_ctx[0]
    cp = ctx.ServiceManager.createInstanceWithContext("com.sun.star.configuration.ConfigurationProvider", ctx)
    arg = uno.createUnoStruct("com.sun.star.beans.PropertyValue")
    arg.Name, arg.Value = "nodepath", path
    kind = "ConfigurationUpdateAccess" if update else "ConfigurationAccess"
    return cp.createInstanceWithArguments("com.sun.star.configuration." + kind, (arg,))


desktop_ctx = [None]


def settings_tests(desktop, macro):
    """The settings dialog, filled and saved without being shown, changes the next run; then back to the defaults."""
    doc = desktop.loadComponentFromURL("private:factory/swriter", "_blank", 0, ())
    provider = doc.getScriptProvider()
    dlg = provider.getScript(macro["settings_dialog"]).invoke((), (), ())[0]
    names = ["Ascii", "Dictionary", "KeepHardSignAfterO", "TsFinal", "SkipUrls", "OK", "Cancel"]
    check("settings: dialog has the five options and two buttons", [dlg.getControl(n) is not None for n in names], [True] * 7)
    check("settings: defaults shown", [dlg.getControl(k).getModel().State for k in ("Ascii", "Dictionary", "SkipUrls")], [0, 1, 1])
    dlg.getControl("Ascii").getModel().State = 1
    provider.getScript(macro["settings_save"]).invoke((dlg,), (), ())
    dlg.dispose()
    check("settings: saved", config(desktop, "/uz.jaybi.UzTranslit/Settings").Ascii, True)
    doc.getText().setString("Ўзбекистон")
    run_macro(desktop, doc, macro["cyr_to_lat"])
    check("settings: plain apostrophe used by the next run", doc.getText().getString(), "O'zbekiston")
    dlg = provider.getScript(macro["settings_dialog"]).invoke((), (), ())[0]
    check("settings: dialog shows the saved value", dlg.getControl("Ascii").getModel().State, 1)
    dlg.getControl("Ascii").getModel().State = 0
    provider.getScript(macro["settings_save"]).invoke((dlg,), (), ())
    dlg.dispose()
    doc.getText().setString("Ўзбекистон")
    run_macro(desktop, doc, macro["cyr_to_lat"])
    check("settings: back to ʻ", doc.getText().getString(), "Oʻzbekiston")
    doc.close(True)


def calc_tests(desktop, macro):
    doc = desktop.loadComponentFromURL("private:factory/scalc", "_blank", 0, ())
    sheet = doc.Sheets.getByIndex(0)
    a1 = sheet.getCellRangeByName("A1")
    add_runs(a1.getText(), [("ТОШ", True), ("КЕНТ", False)])
    sheet.getCellRangeByName("A2").setString("Пойтахт")
    sheet.getCellRangeByName("A3").setFormula("=LEN(A2)")
    sheet.getAnnotations().insertNew(sheet.getCellRangeByName("A2").getCellAddress(), "Изоҳ")
    doc.CurrentController.select(sheet.getCellRangeByName("A1:A3"))

    run_macro(desktop, doc, macro["auto_to_lat"])
    check("calc: automatic calculation back on", doc.isAutomaticCalculationEnabled(), True)
    check("calc: formula recalculated", sheet.getCellRangeByName("A3").getValue(), 7.0)
    a1 = sheet.getCellRangeByName("A1")  # fresh objects: paragraphs enumerated before the macro keep stale lengths
    check("calc: rich text in a cell keeps its runs", portions(paragraphs(a1.getText())[0]), [("TOSH", True), ("KENT", False)])
    check("calc: plain cell", sheet.getCellRangeByName("A2").getString(), "Poytaxt")
    check("calc: formula untouched", sheet.getCellRangeByName("A3").getFormula(), "=LEN(A2)")
    check("calc: comment", sheet.getAnnotations().getByIndex(0).getString(), "Izoh")
    doc.close(True)


def impress_tests(desktop, macro):
    doc = desktop.loadComponentFromURL("private:factory/simpress", "_blank", 0, ())
    page = doc.DrawPages.getByIndex(0)
    shape = doc.createInstance("com.sun.star.drawing.TextShape")
    page.add(shape)
    add_runs(shape, [("Ўзбекистон ", False), ("ШАҲ", True), ("АРЛАРИ", False)])
    shape2 = doc.createInstance("com.sun.star.drawing.TextShape")
    page.add(shape2)
    add_runs(shape2, [("Ш", True), ("аҳар", False)])

    run_macro(desktop, doc, macro["auto_to_new"])
    check("impress: shape runs", portions(paragraphs(shape)[0]), [("Özbekiston ", False), ("ŞAH", True), ("ARLARI", False)])
    check("impress: one bold letter first", portions(paragraphs(shape2)[0]), [("Ş", True), ("ahar", False)])
    doc.close(True)


def edition(name, port):
    oxt, url, names = EDITIONS[name]
    macro = {k: url % v for k, v in names.items()}
    work = os.path.join(WORK, name)
    shutil.rmtree(work, ignore_errors=True)
    profile = os.path.join(work, "profile")
    os.makedirs(profile)
    prof_url = uno.systemPathToFileUrl(profile)
    subprocess.run(["soffice", "-env:UserInstallation=" + prof_url, "--headless", "--norestore", "--terminate_after_init"],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=120)
    subprocess.run(["unopkg", "add", "-env:UserInstallation=" + prof_url, "--suppress-license", os.path.join(ROOT, "libreoffice", oxt)],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=300)
    print("== %s edition (%s)" % (name, oxt))
    proc, ctx = start_office(profile, port)
    try:
        desktop = ctx.ServiceManager.createInstanceWithContext("com.sun.star.frame.Desktop", ctx)
        desktop_ctx[0] = ctx
        try:
            startup_tests(desktop, macro, name)
        except Exception as e:
            failures.append("startup_tests: %s" % e)
            print("  FAIL startup_tests raised %s" % getattr(e, "Message", e))
        for fn in (writer_tests, calc_tests, impress_tests, settings_tests):
            try:
                fn(desktop, macro)
            except Exception as e:  # a macro error is a failure, not a crash of the whole run
                failures.append("%s: %s" % (fn.__name__, e))
                print("  FAIL %s raised %s" % (fn.__name__, getattr(e, "Message", e)))
    finally:
        try:
            desktop.terminate()
        except Exception:
            pass
        time.sleep(1)
        if proc.poll() is None:
            proc.kill()


def split_tests():
    """The Python edition's _split against its definition (each cut where the conversion of all text before it
    ends), on the differential corpus cut into random runs. Needs no running office."""
    import importlib.util
    import json
    import random
    path = os.path.join(ROOT, "libreoffice", "extension", "uztranslit_lo.py")
    spec = importlib.util.spec_from_file_location("uztranslit_lo", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    diff = os.path.join(ROOT, "build", "differential.json")
    if not os.path.exists(diff):
        print("== python split: skipped (run node tools/make_differential.mjs)")
        return
    print("== python split (linear) against the prefix-by-prefix definition")
    rng, plain, n, bad = random.Random(7), mod.convert, 0, 0
    for c in json.load(open(diff, encoding="utf-8"))["cases"]:
        if c["from"] == "auto":
            continue
        o = c["options"]
        mod._options[0] = o  # _split converts with the options of the run
        text, texts, i = c["in"], [], 0
        while i < len(text):
            k = rng.randint(1, 8)
            texts.append(text[i:i + k])
            i += k
        whole = plain(text, c["from"], c["to"], o)
        want = None
        if whole != text:
            want, prev, b = [], 0, 0
            for j, piece in enumerate(texts):
                b += len(piece)
                cur = len(whole) if j == len(texts) - 1 else min(len(plain(text[:b], c["from"], c["to"], o)), len(whole))
                cur = max(cur, prev)
                want.append(whole[prev:cur])
                prev = cur
        got = mod._split(texts, c["from"], c["to"])
        n += 1
        if got != want:
            bad += 1
            if bad <= 5:
                print("  FAIL %s->%s %r\n       want %r\n       got  %r" % (c["from"], c["to"], texts, want, got))
        if n >= 3000:
            break
    mod._options[0] = None
    if bad:
        failures.append("python split: %d of %d" % (bad, n))
    else:
        print("  ok   %d paragraphs" % n)


def formula_tests(port):
    """=UZCONVERT() and friends with UzTranslitLO.bas in My Macros ▸ Standard (docs/LIBREOFFICE_INSTALL.md, method B).
    LibreOffice does not call Basic functions of an extension's library from a cell (#NAME?, or #VALUE! once loaded)."""
    import make_lo_basic
    work = os.path.join(WORK, "formulas")
    shutil.rmtree(work, ignore_errors=True)
    profile = os.path.join(work, "profile")
    os.makedirs(profile)
    subprocess.run(["soffice", "-env:UserInstallation=" + uno.systemPathToFileUrl(profile), "--headless", "--norestore", "--terminate_after_init"],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=120)
    make_lo_basic.install_into_profile(os.path.join(profile, "user", "basic"), {"Standard": {
        "UzTranslitLO": open(os.path.join(ROOT, "libreoffice", "UzTranslitLO.bas"), encoding="utf-8").read()}})
    print("== Calc formulas (UzTranslitLO.bas in My Macros)")
    proc, ctx = start_office(profile, port)
    try:
        desktop = ctx.ServiceManager.createInstanceWithContext("com.sun.star.frame.Desktop", ctx)
        doc = desktop.loadComponentFromURL("private:factory/scalc", "_blank", 0, ())
        sheet = doc.Sheets.getByIndex(0)
        sheet.getCellRangeByName("B1").setString("Toshkent shahri")
        cells = {"A1": ('=UZCONVERT(B1;"lat";"new")', "Toşkent şahri"), "A2": ('=UZCONVERT("Шаҳар";"auto";"lat")', "Shahar"),
                 "A3": ('=UZDETECT("Özbekiston")', "new"), "A4": ('=UZLATTOCYR(B1)', "Тошкент шаҳри")}
        for k, (f, _) in cells.items():
            sheet.getCellRangeByName(k).setFormula(f)
        doc.calculateAll()
        for k, (f, want) in cells.items():
            check("calc formula " + f, sheet.getCellRangeByName(k).getString(), want)
        doc.close(True)
    except Exception as e:
        failures.append("formula_tests: %s" % e)
        print("  FAIL formula_tests raised %s" % getattr(e, "Message", e))
    finally:
        try:
            desktop.terminate()
        except Exception:
            pass
        time.sleep(1)
        if proc.poll() is None:
            proc.kill()


def has_python_provider():
    # the Python script provider ships with LibreOffice on Windows/macOS, as a separate package on Debian/Ubuntu
    for d in ("/usr/lib/libreoffice/program", "/opt/libreoffice/program"):
        if os.path.exists(os.path.join(d, "pythonscript.py")):
            return True
    return False


def main():
    which = sys.argv[1] if len(sys.argv) > 1 else "all"
    names = ["basic", "python"] if which == "all" else [which]
    if "python" in names:
        split_tests()
    if "basic" in names:
        formula_tests(2089)
    for i, name in enumerate(names):
        if name == "python" and not has_python_provider():
            print("== python edition skipped: LibreOffice's Python script provider is not installed")
            continue
        edition(name, 2091 + i)
    print("%d failed" % len(failures) if failures else "all extension checks passed")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
