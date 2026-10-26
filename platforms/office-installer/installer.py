#!/usr/bin/env python3
"""UzTranslit for Microsoft Office — installs the converter and its ribbon tab into Word and Excel (2007 and later,
Windows). Built into UzTranslit-Office-Setup.exe by build.py (PyInstaller); see README.md.

What it does, per application:
  1. allows programmatic access to VBA projects for the moment (AccessVBOM in HKCU; the old value is put back),
  2. starts a hidden instance of Word / Excel through COM, imports office-vba/UzTranslit.bas and UzTranslitRibbon.bas
     into a new file and saves it as UzTranslit.dotm / UzTranslit.xlam,
  3. adds the UzTranslit ribbon tab to that file (tools/add_ribbon.py: office-vba/ribbon/customUI*.xml + icons),
  4. copies it into the application's startup folder (Word: STARTUP, Excel: XLSTART), which loads it with every
     document and is a trusted location, so the macros run without a warning.
Normal.dotm and PERSONAL.XLSB are never touched.

usage: installer.py                            window with Install / Uninstall
       installer.py --install [--word] [--excel] [--quiet]
       installer.py --uninstall [--quiet]
       installer.py --check                    the bundled files are present (CI smoke test, no Office needed)
"""
import argparse
import contextlib
import json
import logging
import os
import shutil
import sys
import tempfile
import threading
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = getattr(sys, "_MEIPASS", None) or os.path.dirname(os.path.dirname(HERE))
if not getattr(sys, "frozen", False):
    sys.path.insert(0, os.path.join(ROOT, "tools"))
import add_ribbon  # noqa: E402

VBA_DIR = os.path.join(ROOT, "office-vba")
MODULES = [os.path.join(VBA_DIR, "UzTranslit.bas"), os.path.join(VBA_DIR, "UzTranslitRibbon.bas")]
RIBBON_DIR = os.path.join(VBA_DIR, "ribbon")
STATE_DIR = os.path.join(os.environ.get("LOCALAPPDATA") or os.path.expanduser("~"), "UzTranslit")
APPDATA = os.environ.get("APPDATA") or os.path.expanduser("~")

log = logging.getLogger("uztranslit-office")


class Host:
    def __init__(self, name, progid, file_name, file_format, default_startup):
        self.name, self.progid, self.file_name = name, progid, file_name
        self.file_format = file_format          # wdFormatXMLTemplateMacroEnabled = 15, xlOpenXMLAddIn = 55
        self.default_startup = default_startup

    def security_key(self, version):
        return r"Software\Microsoft\Office\%s\%s\Security" % (version, self.name)

    def policy_key(self, version):
        return r"Software\Policies\Microsoft\Office\%s\%s\Security" % (version, self.name)


WORD = Host("Word", "Word.Application", "UzTranslit.dotm", 15, os.path.join(APPDATA, "Microsoft", "Word", "STARTUP"))
EXCEL = Host("Excel", "Excel.Application", "UzTranslit.xlam", 55, os.path.join(APPDATA, "Microsoft", "Excel", "XLSTART"))
HOSTS = [WORD, EXCEL]


class InstallError(Exception):
    pass


# ---------------------------------------------------------------- Windows: registry and COM (replaced in tests)

class Registry:
    """The few registry operations the installer needs; HKCU unless a root is given."""

    def _root(self, root):
        import winreg
        return {"HKCU": winreg.HKEY_CURRENT_USER, "HKLM": winreg.HKEY_LOCAL_MACHINE, "HKCR": winreg.HKEY_CLASSES_ROOT}[root]

    def get(self, path, name, root="HKCU"):
        import winreg
        try:
            with winreg.OpenKey(self._root(root), path) as k:
                return winreg.QueryValueEx(k, name)[0]
        except OSError:
            return None

    def set_dword(self, path, name, value):
        import winreg
        with winreg.CreateKeyEx(winreg.HKEY_CURRENT_USER, path, 0, winreg.KEY_SET_VALUE) as k:
            winreg.SetValueEx(k, name, 0, winreg.REG_DWORD, int(value))

    def delete(self, path, name):
        import winreg
        try:
            with winreg.OpenKey(winreg.HKEY_CURRENT_USER, path, 0, winreg.KEY_SET_VALUE) as k:
                winreg.DeleteValue(k, name)
        except OSError:
            pass


class Com:
    def dispatch(self, progid):
        import win32com.client
        return win32com.client.DispatchEx(progid)    # a new, separate instance: the user's open windows are left alone


def office_version(host, reg):
    """'16.0' for Office 2016 – 2024 / Microsoft 365, '15.0' for 2013 …; None when the application is not installed."""
    cur = reg.get(host.progid + r"\CurVer", "", root="HKCR")        # e.g. "Word.Application.16"
    if not cur:
        return None
    major = cur.rsplit(".", 1)[-1]
    return major + ".0" if major.isdigit() else None


@contextlib.contextmanager
def vba_project_access(host, version, reg):
    """Trust access to the VBA project object model while the module is imported, then restore the user's setting."""
    for root in ("HKCU", "HKLM"):
        if reg.get(host.policy_key(version), "AccessVBOM", root=root) == 0:
            raise InstallError("%s: access to VBA projects is switched off by a group policy (%s\\%s). Ask your "
                               "administrator, or import the modules by hand (docs/OFFICE_INSTALL.md)."
                               % (host.name, root, host.policy_key(version)))
    key = host.security_key(version)
    before = reg.get(key, "AccessVBOM")
    reg.set_dword(key, "AccessVBOM", 1)
    try:
        yield
    finally:
        if before is None:
            reg.delete(key, "AccessVBOM")
        else:
            reg.set_dword(key, "AccessVBOM", before)


# ---------------------------------------------------------------- building and placing the file

def build_file(host, out_path, com):
    """Imports the modules in a hidden instance of the application and saves out_path; returns its startup folder."""
    log.info("%s: starting a hidden instance", host.name)
    try:
        app = com.dispatch(host.progid)
    except Exception as e:
        raise InstallError("%s could not be started (%s)." % (host.name, e))
    try:
        app.Visible = False
        app.DisplayAlerts = 0
        with contextlib.suppress(Exception):
            app.AutomationSecurity = 3              # msoAutomationSecurityForceDisable: run no macro while we work
        startup = ""
        with contextlib.suppress(Exception):
            startup = app.StartupPath or ""
        doc = app.Documents.Add() if host is WORD else app.Workbooks.Add()
        try:
            try:
                components = doc.VBProject.VBComponents
            except Exception as e:
                raise InstallError("%s does not allow access to the VBA project (%s). In %s: File > Options > Trust "
                                   "Center > Trust Center Settings > Macro Settings > tick \"Trust access to the VBA "
                                   "project object model\", then run the installer again." % (host.name, e, host.name))
            for path in MODULES:
                log.info("%s: importing %s", host.name, os.path.basename(path))
                try:
                    components.Import(path)
                except Exception as e:
                    raise InstallError("%s: importing %s failed (%s)." % (host.name, os.path.basename(path), e))
            try:
                if host is WORD:
                    try:
                        doc.SaveAs2(FileName=out_path, FileFormat=host.file_format)
                    except AttributeError:
                        doc.SaveAs(FileName=out_path, FileFormat=host.file_format)   # Word 2007 has no SaveAs2
                else:
                    doc.SaveAs(out_path, host.file_format)
            except Exception as e:
                raise InstallError("%s: saving %s failed (%s)." % (host.name, host.file_name, e))
        finally:
            with contextlib.suppress(Exception):
                doc.Close(False)
        return startup
    finally:
        with contextlib.suppress(Exception):
            app.Quit(0) if host is WORD else app.Quit()


def check_file(path):
    with zipfile.ZipFile(path) as z:
        names = set(z.namelist())
    missing = [n for n in ("customUI/customUI14.xml", "customUI/customUI.xml") if n not in names]
    if not any(n.endswith("vbaProject.bin") for n in names):
        missing.append("vbaProject.bin")
    if missing:
        raise InstallError("%s is incomplete: %s missing." % (os.path.basename(path), ", ".join(missing)))


def place(host, src, folder, on_locked):
    """Copies src into folder; while the target is locked (the application has the old version open), asks
    on_locked(host) whether to try again."""
    os.makedirs(folder, exist_ok=True)
    dst = os.path.join(folder, host.file_name)
    while True:
        try:
            shutil.copyfile(src, dst)
            return dst
        except PermissionError:
            log.warning("%s: %s is in use", host.name, dst)
            if not on_locked(host):
                raise InstallError("%s is in use: close %s and run the installer again." % (dst, host.name))


def load_state():
    try:
        with open(os.path.join(STATE_DIR, "office.json"), encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def save_state(state):
    os.makedirs(STATE_DIR, exist_ok=True)
    with open(os.path.join(STATE_DIR, "office.json"), "w", encoding="utf-8") as f:
        json.dump(state, f, indent=2)


def installed_hosts(reg):
    return [h for h in HOSTS if office_version(h, reg)]


def install(hosts, on_locked=lambda host: False, reg=None, com=None):
    """Installs into every host given; returns {host name: installed path}. Raises InstallError on the first failure
    after logging it; hosts that are not installed are skipped."""
    reg, com = reg or Registry(), com or Com()
    for path in MODULES:
        if not os.path.isfile(path):
            raise InstallError("Bundled file missing: %s" % path)
    state, done = load_state(), {}
    for host in hosts:
        version = office_version(host, reg)
        if not version:
            log.info("%s is not installed: skipped", host.name)
            continue
        log.info("%s %s found", host.name, version)
        with tempfile.TemporaryDirectory(prefix="uztranslit-") as tmp:
            built = os.path.join(tmp, host.file_name)
            with vba_project_access(host, version, reg):
                startup = build_file(host, built, com)
            add_ribbon.add_ribbon(built, built, ribbon=RIBBON_DIR)
            check_file(built)
            dst = place(host, built, startup or host.default_startup, on_locked)
        done[host.name] = state[host.name] = dst
        save_state(state)
        log.info("%s: installed %s", host.name, dst)
    return done


def uninstall(hosts=HOSTS):
    state, removed = load_state(), []
    for host in hosts:
        for path in {state.get(host.name), os.path.join(host.default_startup, host.file_name)} - {None}:
            try:
                os.remove(path)
                removed.append(path)
                log.info("%s: removed %s", host.name, path)
            except FileNotFoundError:
                pass
            except PermissionError:
                raise InstallError("%s is in use: close %s and try again." % (path, host.name))
        state.pop(host.name, None)
    save_state(state)
    if not removed:
        log.info("Nothing to remove")
    return removed


def self_check():
    """The exe carries everything it needs (run by CI, where there is no Office)."""
    for path in MODULES + [os.path.join(RIBBON_DIR, "customUI.xml"), os.path.join(RIBBON_DIR, "customUI14.xml")]:
        if not os.path.isfile(path):
            raise InstallError("missing: %s" % path)
    images = os.listdir(os.path.join(RIBBON_DIR, "images"))
    if len(add_ribbon.ribbon_parts(RIBBON_DIR)) != 4 + len(images):
        raise InstallError("ribbon parts incomplete")
    return "ok: %d modules, ribbon with %d images" % (len(MODULES), len(images))


# ---------------------------------------------------------------- interface

TEXT = {
    "uz": {"title": "UzTranslit — Microsoft Office", "intro": "Word va Excelga «UzTranslit» yorligʻini oʻrnatadi: "
           "Yangi lotin, Lotin 1995, Кирилл tugmalari har bir hujjatda. Word va Excelni yopib qoʻying.",
           "install": "Oʻrnatish", "uninstall": "Olib tashlash", "close": "Yopish", "missing": "(oʻrnatilmagan)",
           "locked": "{app} ochiq va eski faylni band qilgan. {app}ni yoping va «Retry»ni bosing.",
           "ok": "Tayyor. {apps}ni oching: «UzTranslit» yorligʻi paydo boʻladi.", "removed": "Olib tashlandi.",
           "failed": "Xato"},
    "ru": {"title": "UzTranslit — Microsoft Office", "intro": "Устанавливает вкладку «UzTranslit» в Word и Excel: "
           "кнопки Yangi lotin, Lotin 1995, Кирилл в каждом документе. Закройте Word и Excel.",
           "install": "Установить", "uninstall": "Удалить", "close": "Закрыть", "missing": "(не установлен)",
           "locked": "{app} открыт и держит старый файл. Закройте {app} и нажмите «Повтор».",
           "ok": "Готово. Откройте {apps}: появится вкладка «UzTranslit».", "removed": "Удалено.", "failed": "Ошибка"},
    "en": {"title": "UzTranslit — Microsoft Office", "intro": "Installs the \"UzTranslit\" tab in Word and Excel: "
           "Yangi lotin, Lotin 1995 and Кирилл buttons in every document. Please close Word and Excel.",
           "install": "Install", "uninstall": "Uninstall", "close": "Close", "missing": "(not installed)",
           "locked": "{app} is open and holds the old file. Close {app} and press Retry.",
           "ok": "Done. Open {apps}: the \"UzTranslit\" tab is there.", "removed": "Removed.", "failed": "Error"},
}


def ui_language():
    try:
        import ctypes
        primary = ctypes.windll.kernel32.GetUserDefaultUILanguage() & 0x3FF
        return {0x43: "uz", 0x19: "ru"}.get(primary, "en")
    except Exception:
        return "en"


def setup_logging(extra=None):
    os.makedirs(STATE_DIR, exist_ok=True)
    log.setLevel(logging.INFO)
    fh = logging.FileHandler(os.path.join(STATE_DIR, "office-installer.log"), encoding="utf-8")
    fh.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
    log.addHandler(fh)
    if extra:
        log.addHandler(extra)


def run_gui():
    import tkinter as tk
    from tkinter import messagebox, scrolledtext
    t = TEXT[ui_language()]
    reg = Registry()
    root = tk.Tk()
    root.title(t["title"])
    root.minsize(520, 360)
    tk.Label(root, text=t["intro"], wraplength=500, justify="left").pack(padx=12, pady=(12, 6), anchor="w")
    found = installed_hosts(reg)
    chosen = {}
    for h in HOSTS:
        chosen[h.name] = tk.BooleanVar(value=h in found)
        tk.Checkbutton(root, text=h.name + ("" if h in found else " " + t["missing"]), variable=chosen[h.name],
                       state="normal" if h in found else "disabled").pack(padx=12, anchor="w")
    box = scrolledtext.ScrolledText(root, height=12, state="disabled")
    box.pack(fill="both", expand=True, padx=12, pady=6)

    class BoxHandler(logging.Handler):
        def emit(self, record):
            msg = self.format(record) + "\n"
            root.after(0, lambda: (box.configure(state="normal"), box.insert("end", msg), box.see("end"),
                                   box.configure(state="disabled")))
    setup_logging(BoxHandler())

    def ask_main_thread(fn):
        answer, ready = {}, threading.Event()
        root.after(0, lambda: (answer.setdefault("v", fn()), ready.set()))
        ready.wait()
        return answer["v"]

    def on_locked(host):
        return ask_main_thread(lambda: messagebox.askretrycancel(t["title"], t["locked"].format(app=host.name)))

    buttons = tk.Frame(root)
    buttons.pack(fill="x", padx=12, pady=(0, 12))

    def work(job):
        for b in buttons.winfo_children():
            b.configure(state="disabled")

        def run():
            import pythoncom
            pythoncom.CoInitialize()
            try:
                message = job()
                root.after(0, lambda: messagebox.showinfo(t["title"], message))
            except Exception as e:
                err = str(e)
                log.error("%s", err)
                root.after(0, lambda: messagebox.showerror(t["failed"], err))
            finally:
                pythoncom.CoUninitialize()
                root.after(0, lambda: [b.configure(state="normal") for b in buttons.winfo_children()])
        threading.Thread(target=run, daemon=True).start()

    def do_install():
        hosts = [h for h in HOSTS if chosen[h.name].get()]
        done = install(hosts, on_locked, reg)
        return t["ok"].format(apps=", ".join(done) or "Office")

    def do_uninstall():
        uninstall()
        return t["removed"]

    tk.Button(buttons, text=t["install"], width=14, command=lambda: work(do_install)).pack(side="left")
    tk.Button(buttons, text=t["uninstall"], width=14, command=lambda: work(do_uninstall)).pack(side="left", padx=6)
    tk.Button(buttons, text=t["close"], width=10, command=root.destroy).pack(side="right")
    root.mainloop()


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--install", action="store_true")
    ap.add_argument("--uninstall", action="store_true")
    ap.add_argument("--word", action="store_true", help="only Word (with --install)")
    ap.add_argument("--excel", action="store_true", help="only Excel (with --install)")
    ap.add_argument("--quiet", action="store_true", help="no window, no questions; the exit code tells the result")
    ap.add_argument("--check", action="store_true")
    a = ap.parse_args(argv)
    if a.check:
        try:
            result = self_check()
        except InstallError as e:
            result = "FAILED " + str(e)
        if sys.stdout:                          # a --noconsole exe has none: the exit code tells the result
            print(result)
        return 0 if result.startswith("ok") else 1
    if not (a.install or a.uninstall):
        run_gui()
        return 0
    setup_logging(None if a.quiet or sys.stderr is None else logging.StreamHandler())
    try:
        if a.uninstall:
            uninstall()
        else:
            hosts = [h for h, only in ((WORD, a.word), (EXCEL, a.excel)) if only] or HOSTS
            install(hosts)
        return 0
    except InstallError as e:
        log.error("%s", e)
        return 1


if __name__ == "__main__":
    sys.exit(main())
