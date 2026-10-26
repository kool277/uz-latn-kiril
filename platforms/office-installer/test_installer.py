#!/usr/bin/env python3
"""Tests installer.py without Office: fake Word/Excel COM objects record what the installer asks of them and save a
real Office Open XML package with a VBA part; the registry is a dictionary. Everything else — ribbon injection,
checks, copying into the startup folders, the retry on a locked file, the state file, uninstall — runs for real.
usage: python3 platforms/office-installer/test_installer.py"""
import logging
import os
import shutil
import sys
import tempfile
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import installer  # noqa: E402

installer.log.addHandler(logging.NullHandler())      # the expected "in use" warnings stay out of the output

failures = []


def check(name, ok, detail=""):
    print("  %s %s%s" % ("ok  " if ok else "FAIL", name, "" if ok else "  " + str(detail)))
    if not ok:
        failures.append(name)


class FakeRegistry:
    def __init__(self, versions=("Word", "Excel"), values=None):
        self.values = dict(values or {})
        for app in versions:
            self.values[("HKCR", app + r".Application\CurVer", "")] = app + ".Application.16"
        self.history = []

    def get(self, path, name, root="HKCU"):
        return self.values.get((root, path, name))

    def set_dword(self, path, name, value):
        self.history.append(("set", path, name, value))
        self.values[("HKCU", path, name)] = value

    def delete(self, path, name):
        self.history.append(("delete", path, name))
        self.values.pop(("HKCU", path, name), None)


def write_package(path, vba=True):
    with zipfile.ZipFile(path, "w") as z:
        z.writestr("[Content_Types].xml", '<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/'
                   'package/2006/content-types"></Types>')
        z.writestr("_rels/.rels", '<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/'
                   'package/2006/relationships"></Relationships>')
        if vba:
            z.writestr("word/vbaProject.bin", b"\xd0\xcf\x11\xe0fake")


class FakeComponents:
    def __init__(self, app):
        self.app = app

    def Import(self, path):
        if self.app.fail_import:
            raise RuntimeError("import refused")
        self.app.imported.append(os.path.basename(path))


class FakeDoc:
    def __init__(self, app):
        self.app = app

    @property
    def VBProject(self):
        if not self.app.registry_allows():
            raise RuntimeError("Programmatic access to Visual Basic Project is not trusted")
        return type("P", (), {"VBComponents": FakeComponents(self.app)})()

    def SaveAs2(self, FileName, FileFormat):
        self.app.saved.append((FileName, FileFormat))
        write_package(FileName, vba=bool(self.app.imported))

    def SaveAs(self, FileName, FileFormat):
        self.SaveAs2(FileName, FileFormat)

    def Close(self, save):
        self.app.closed = True


class FakeApp:
    def __init__(self, com, progid):
        self.com, self.progid = com, progid
        self.imported, self.saved, self.closed, self.quit = [], [], False, False
        self.fail_import = com.fail_import
        self.StartupPath = com.startup.get(progid, "")
        self.Documents = self.Workbooks = type("C", (), {"Add": lambda _: FakeDoc(self)})()

    def registry_allows(self):
        app = self.progid.split(".")[0]
        return self.com.reg.get(r"Software\Microsoft\Office\16.0\%s\Security" % app, "AccessVBOM") == 1

    def Quit(self, *a):
        self.quit = True


class FakeCom:
    def __init__(self, reg, startup=None, fail_import=False):
        self.reg, self.startup, self.fail_import, self.apps = reg, startup or {}, fail_import, []

    def dispatch(self, progid):
        app = FakeApp(self, progid)
        self.apps.append(app)
        return app


def fresh(tmp):
    installer.STATE_DIR = os.path.join(tmp, "state")
    installer.WORD.default_startup = os.path.join(tmp, "Word", "STARTUP")
    installer.EXCEL.default_startup = os.path.join(tmp, "Excel", "XLSTART")


def names(path):
    with zipfile.ZipFile(path) as z:
        return set(z.namelist())


def main():
    print("installer --check:")
    check("bundled files present", installer.self_check().startswith("ok"))

    tmp = tempfile.mkdtemp(prefix="uzt-installer-")
    try:
        print("install into Word and Excel:")
        fresh(tmp)
        key_w, key_x = r"Software\Microsoft\Office\16.0\Word\Security", r"Software\Microsoft\Office\16.0\Excel\Security"
        reg = FakeRegistry(values={("HKCU", key_x, "AccessVBOM"): 0})
        excel_startup = os.path.join(tmp, "custom-xlstart")
        com = FakeCom(reg, startup={"Excel.Application": excel_startup})
        done = installer.install(installer.HOSTS, reg=reg, com=com)
        word, excel = com.apps
        check("both installed", sorted(done) == ["Excel", "Word"], done)
        check("modules imported in order", word.imported == excel.imported == ["UzTranslit.bas", "UzTranslitRibbon.bas"])
        check("Word saved as .dotm (format 15)", word.saved and word.saved[0][1] == 15, word.saved)
        check("Excel saved as .xlam (format 55)", excel.saved and excel.saved[0][1] == 55, excel.saved)
        check("documents closed and both instances quit", word.closed and excel.closed and word.quit and excel.quit)
        dotm = os.path.join(installer.WORD.default_startup, "UzTranslit.dotm")
        xlam = os.path.join(excel_startup, "UzTranslit.xlam")
        check("Word: default STARTUP folder when Word reports none", done.get("Word") == dotm and os.path.isfile(dotm))
        check("Excel: the startup folder Excel reports", done.get("Excel") == xlam and os.path.isfile(xlam))
        for path in (dotm, xlam):
            n = names(path)
            check("%s has the ribbon and its icons" % os.path.basename(path),
                  {"customUI/customUI.xml", "customUI/customUI14.xml", "customUI/images/to_new.png"} <= n, n)
        check("AccessVBOM removed again where it was not set", ("HKCU", key_w, "AccessVBOM") not in reg.values)
        check("AccessVBOM put back to the user's 0", reg.values.get(("HKCU", key_x, "AccessVBOM")) == 0)
        check("state file lists both", sorted(installer.load_state()) == ["Excel", "Word"])

        print("running it again replaces the files:")
        before = os.path.getmtime(dotm)
        os.utime(dotm, (before - 100, before - 100))
        installer.install([installer.WORD], reg=reg, com=FakeCom(reg))
        check("Word file rewritten", os.path.getmtime(dotm) > before - 100)

        print("a locked file:")
        real_copy, calls = installer.shutil.copyfile, []

        def locked_once(src, dst):
            if not calls:
                calls.append(1)
                raise PermissionError(32, "in use")
            return real_copy(src, dst)
        installer.shutil.copyfile = locked_once
        asked = []
        installer.install([installer.WORD], on_locked=lambda h: asked.append(h.name) or True, reg=reg, com=FakeCom(reg))
        check("asks, then retries and succeeds", asked == ["Word"] and os.path.isfile(dotm), asked)
        calls.clear()
        try:
            installer.install([installer.WORD], on_locked=lambda h: False, reg=reg, com=FakeCom(reg))
            check("gives up when the user cancels", False)
        except installer.InstallError as e:
            check("gives up when the user cancels", "in use" in str(e), e)
        finally:
            installer.shutil.copyfile = real_copy

        print("errors:")
        policy = FakeRegistry(values={("HKCU", r"Software\Policies\Microsoft\Office\16.0\Word\Security", "AccessVBOM"): 0})
        com = FakeCom(policy)
        try:
            installer.install([installer.WORD], reg=policy, com=com)
            check("group policy: clear error", False)
        except installer.InstallError as e:
            check("group policy: clear error, Office not started", "group policy" in str(e) and not com.apps, e)
        check("group policy: registry left alone", not policy.history, policy.history)

        class NoTrust(FakeRegistry):
            def set_dword(self, path, name, value):           # e.g. a setting Office ignores
                self.history.append(("set", path, name, value))
        nt = NoTrust()
        com = FakeCom(nt)
        try:
            installer.install([installer.WORD], reg=nt, com=com)
            check("VBA project not accessible: clear error", False)
        except installer.InstallError as e:
            check("VBA project not accessible: clear error", "Trust access to the VBA project" in str(e), e)
        check("... and Word quit anyway", com.apps and com.apps[0].quit)

        com = FakeCom(reg, fail_import=True)
        try:
            installer.install([installer.EXCEL], reg=reg, com=com)
            check("failed import: clear error", False)
        except installer.InstallError as e:
            check("failed import: clear error, Excel quit", "importing UzTranslit.bas failed" in str(e) and com.apps[0].quit, e)
        check("registry restored after a failure", reg.values.get(("HKCU", key_x, "AccessVBOM")) == 0)

        only_word = FakeRegistry(versions=("Word",))
        com = FakeCom(only_word)
        done = installer.install(installer.HOSTS, reg=only_word, com=com)
        check("Excel not installed: skipped", list(done) == ["Word"] and len(com.apps) == 1, done)
        check("installed_hosts", [h.name for h in installer.installed_hosts(only_word)] == ["Word"])

        print("uninstall:")
        removed = installer.uninstall()
        check("removes both files", not os.path.exists(dotm) and not os.path.exists(xlam), removed)
        check("state emptied", installer.load_state() == {})
        check("nothing left to remove the second time", installer.uninstall() == [])

        print("command line:")
        check("--check exits 0", installer.main(["--check"]) == 0)
    finally:
        shutil.rmtree(tmp)

    print("%d failed" % len(failures))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
