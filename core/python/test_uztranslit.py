#!/usr/bin/env python3
"""Conformance runner: python3 core/python/test_uztranslit.py (exit 1 on failure)"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import uztranslit as U  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
with open(os.path.join(HERE, "..", "..", "spec", "fixtures.json"), encoding="utf-8") as f:
    FX = json.load(f)

passed = failed = 0


def check(tid, got, want, extra=""):
    global passed, failed
    if got == want:
        passed += 1
    else:
        failed += 1
        print("FAIL %s %s\n   want %r\n   got  %r" % (tid, extra, want, got))


for c in FX["cases"]:
    check(c["id"], U.convert(c["in"], c["from"], c["to"]), c["out"], "%s->%s %r" % (c["from"], c["to"], c["in"]))
for r in FX["roundtrips"]:
    there = U.convert(r["in"], r["from"], r["via"])
    check(r["id"], U.convert(there, r["via"], r["from"]), r["in"], "via %r" % there)
for d in FX["detect"]:
    check("detect %r" % d["in"], U.detect(d["in"]), d["expect"])
for o in FX["optional"]:
    options = {"okina": "'", "tutuq": "'"} if o["feature"] == "asciiApostrophe" else {"skipUrls": True}
    check("optional/" + o["feature"], U.convert(o["in"], o["from"], o["to"], options), o["out"])

print("%d passed, %d failed (uztranslit.py v%s)" % (passed, failed, U.VERSION))
sys.exit(1 if failed else 0)
