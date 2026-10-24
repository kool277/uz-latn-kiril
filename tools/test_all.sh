#!/usr/bin/env bash
# Runs every conformance suite that can run on this machine. Exit code 1 on any failure.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0
echo "== Source hygiene (no invisible characters in code)"
( cd "$ROOT" && python3 tools/escape-invisible.py --check $(git ls-files '*.ts' '*.mjs' '*.js' '*.py' '*.bas' '*.html' '*.css' '*.yml' \
    '*.kt' '*.kts' '*.swift' '*.cpp' '*.hpp' '*.h' '*.xml' '*.xcu' | grep -v '^web/test/fixtures/') ) && echo "clean" || fail=1
echo "== Differential corpus"; node "$ROOT/tools/make_differential.mjs" || fail=1
echo "== JS core";      node "$ROOT/core/js/test.js" || fail=1
echo "== Python core";  python3 "$ROOT/core/python/test_uztranslit.py" || fail=1
echo "== WebAssembly core"
( cd "$ROOT/core/wasm" &&
  { [ -x node_modules/.bin/asc ] || npm ci --no-audit --no-fund --silent; } &&
  npm run --silent build && node test.mjs ) || fail=1
if command -v soffice >/dev/null 2>&1 && python3 -c "import uno" 2>/dev/null; then
  echo "== LibreOffice Basic (VBA engine)"
  python3 "$ROOT/tools/make_lo_basic.py" --test >/dev/null && rm -f "$ROOT/build/lo-test/result.txt"
  python3 "$ROOT/tools/lo_run_macro.py" Standard.UzTest.RunAll "$ROOT/build/lo-test/result.txt" | tail -n +2
  { grep -q " 0 failed" "$ROOT/build/lo-test/result.txt" && ! grep -qE " [1-9][0-9]* failed" "$ROOT/build/lo-test/result.txt"; } 2>/dev/null || fail=1
else
  echo "== LibreOffice not available: Basic suite skipped"
fi
echo "== Web engine (fixtures through both engine builds, every document format; LibreOffice round-trips when installed)"
( cd "$ROOT/web" &&
  { [ -d node_modules ] || npm ci --no-audit --no-fund --silent; } &&
  npm run --silent test:engine ) || fail=1
[ $fail -eq 0 ] && echo "ALL SUITES GREEN" || { echo "FAILURES"; exit 1; }
