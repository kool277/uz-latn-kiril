#!/usr/bin/env python3
"""Run a LibreOffice Basic macro headlessly via UNO and print its result file or the compile/runtime error.
usage: python3 tools/lo_run_macro.py Standard.UzTest.RunAll build/lo-test/result.txt

soffice runs with the throwaway profile build/lo-test/profile (override with LO_USER_INSTALLATION),
never with the developer's own LibreOffice profile.
"""
import os
import subprocess
import sys
import time

import uno
from com.sun.star.beans import PropertyValue  # noqa

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
profile = os.environ.get("LO_USER_INSTALLATION") or os.path.join(ROOT, "build", "lo-test", "profile")

macro = sys.argv[1]
result_file = sys.argv[2] if len(sys.argv) > 2 else None
port = 2083
proc = subprocess.Popen(["soffice", "-env:UserInstallation=" + uno.systemPathToFileUrl(os.path.abspath(profile)),
                         "--headless", "--norestore", "--nologo", "--nodefault",
                         "--accept=socket,host=127.0.0.1,port=%d;urp;StarOffice.ComponentContext" % port],
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
try:
    local = uno.getComponentContext()
    resolver = local.ServiceManager.createInstanceWithContext("com.sun.star.bridge.UnoUrlResolver", local)
    ctx = None
    for _ in range(60):
        try:
            ctx = resolver.resolve("uno:socket,host=127.0.0.1,port=%d;urp;StarOffice.ComponentContext" % port)
            break
        except Exception:
            time.sleep(1)
    if ctx is None:
        print("could not connect to soffice")
        sys.exit(2)
    smgr = ctx.ServiceManager
    mspf = smgr.createInstanceWithContext("com.sun.star.script.provider.MasterScriptProviderFactory", ctx)
    sp = mspf.createScriptProvider("")
    script = sp.getScript("vnd.sun.star.script:%s?language=Basic&location=application" % macro)
    try:
        script.invoke((), (), ())
        print("macro finished")
    except Exception as e:  # ScriptErrorRaisedException / ScriptFrameworkErrorException
        msg = getattr(e, "Message", str(e))
        print("MACRO ERROR:", msg)
        for attr in ("scriptName", "language", "lineNum"):
            if hasattr(e, attr):
                print(" ", attr, "=", getattr(e, attr))
    if result_file and os.path.exists(result_file):
        print(open(result_file, encoding="utf-8", errors="replace").read()[:6000])
    elif result_file:
        print("(no result file)")
finally:
    try:
        desktop = smgr.createInstanceWithContext("com.sun.star.frame.Desktop", ctx)
        desktop.terminate()
    except Exception:
        pass
    time.sleep(1)
    if proc.poll() is None:
        proc.kill()
