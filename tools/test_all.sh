#!/usr/bin/env bash
# Runs every conformance suite that can run on this machine. Exit code 1 on any failure.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0
echo "== JS core";      node "$ROOT/core/js/test.js" || fail=1
echo "== Python core";  python3 "$ROOT/core/python/test_uztranslit.py" || fail=1
if command -v soffice >/dev/null 2>&1 && python3 -c "import uno" 2>/dev/null; then
  echo "== LibreOffice Basic (VBA engine)"
  python3 "$ROOT/tools/make_lo_basic.py" --test >/dev/null && rm -f "$ROOT/build/lo-test/result.txt"
  python3 "$ROOT/tools/lo_run_macro.py" Standard.UzTest.RunAll "$ROOT/build/lo-test/result.txt" | tail -n +2
  grep -q " 0 failed" "$ROOT/build/lo-test/result.txt" 2>/dev/null || fail=1
else
  echo "== LibreOffice not available: Basic suite skipped"
fi
echo "== web files";    cp "$ROOT/core/js/uztranslit.js" "$ROOT/web/uztranslit.js" && echo "web/uztranslit.js synced"
[ $fail -eq 0 ] && echo "ALL SUITES GREEN" || { echo "FAILURES"; exit 1; }
