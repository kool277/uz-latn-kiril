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

# differential corpus (node tools/make_differential.mjs): the reference JS core's output on random text
DIFF = os.path.join(HERE, "..", "..", "build", "differential.json")
dfail = 0
if os.path.exists(DIFF):
    with open(DIFF, encoding="utf-8") as f:
        D = json.load(f)
    dpass = 0
    for c in D["cases"]:
        got = U.convert(c["in"], c["from"], c["to"], c["options"])
        if got == c["out"]:
            dpass += 1
        else:
            dfail += 1
            if dfail <= 10:
                print("DIFF %s->%s %r\n   in   %r\n   want %r\n   got  %r" % (c["from"], c["to"], c["options"], c["in"], c["out"], got))
    for d in D["detect"]:
        if U.detect(d["in"]) == d["expect"]:
            dpass += 1
        else:
            dfail += 1
            if dfail <= 10:
                print("DIFF detect %r: want %s got %s" % (d["in"], d["expect"], U.detect(d["in"])))
    print("%d passed, %d failed (differential vs %s)" % (dpass, dfail, D["reference"]))

sys.exit(1 if failed or dfail else 0)
