#!/usr/bin/env bash
# Runs every conformance suite that can run on this machine. Exit code 1 on any failure.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0
mkdir -p "$ROOT/build"
echo "== Source hygiene (no invisible characters in code)"
( cd "$ROOT" && python3 tools/escape-invisible.py --check $(git ls-files '*.ts' '*.mjs' '*.js' '*.py' '*.bas' '*.html' '*.css' '*.yml' \
    '*.kt' '*.kts' '*.swift' '*.cpp' '*.hpp' '*.h' '*.xml' '*.xcu' | grep -v '^web/test/fixtures/') ) && echo "clean" || fail=1
echo "== VBA lint (what the VBA editor would reject)"; python3 "$ROOT/tools/vba_lint.py" "$ROOT"/office-vba/*.bas || fail=1
echo "== Office ribbon (tools/add_ribbon.py)"
python3 "$ROOT/tools/test_add_ribbon.py" > "$ROOT/build/ribbon-test.log" 2>&1 || fail=1
grep -v "^  ok" "$ROOT/build/ribbon-test.log"
echo "== Differential corpus"; node "$ROOT/tools/make_differential.mjs" || fail=1
echo "== Office add-in (manifests, logic against fake hosts)"
node "$ROOT/platforms/office-addin/build.mjs" --check || fail=1
node "$ROOT/platforms/office-addin/test/run.mjs" || fail=1
echo "== JS core";      node "$ROOT/core/js/test.js" || fail=1
echo "== Python core";  python3 "$ROOT/core/python/test_uztranslit.py" || fail=1
echo "== WebAssembly core"
( cd "$ROOT/core/wasm" &&
  { [ -x node_modules/.bin/asc ] || npm ci --no-audit --no-fund --silent; } &&
  npm run --silent build && node test.mjs ) || fail=1
if command -v soffice >/dev/null 2>&1 && python3 -c "import uno" 2>/dev/null; then
  echo "== LibreOffice Basic (VBA engine: fixtures, differential corpus, UzSplitConvert)"
  python3 "$ROOT/tools/make_lo_basic.py" --test >/dev/null && rm -f "$ROOT/build/lo-test/result.txt" "$ROOT/build/lo-test/office.txt"
  python3 "$ROOT/tools/lo_run_macro.py" Standard.UzTest.RunAll "$ROOT/build/lo-test/result.txt" | tail -n +2
  { grep -q " 0 failed" "$ROOT/build/lo-test/result.txt" && ! grep -qE " [1-9][0-9]* failed" "$ROOT/build/lo-test/result.txt"; } 2>/dev/null || fail=1
  echo "== MS Office module, document macros included, compiles (LibreOffice VBA mode)"
  python3 "$ROOT/tools/lo_run_macro.py" UzOffice.UzCheck.Run "$ROOT/build/lo-test/office.txt" | tail -n +2
  grep -q "^office module compiled: " "$ROOT/build/lo-test/office.txt" 2>/dev/null || { echo "FAIL: the module did not compile"; fail=1; }
  grep -q "^UzSelfTest: [0-9]* passed, 0 failed" "$ROOT/build/lo-test/office.txt" 2>/dev/null || { echo "FAIL: UzSelfTest"; fail=1; }
  echo "== LibreOffice extensions end to end (Writer, Calc, Impress; both editions)"
  python3 "$ROOT/tools/lo_extension_test.py" || fail=1
else
  echo "== LibreOffice not available: Basic suite skipped"
fi
if [ -n "${GITHUB_ACTIONS:-}" ]; then :
elif command -v qmake6 >/dev/null 2>&1 || docker image inspect uztranslit-qt >/dev/null 2>&1; then
  echo "== Qt desktop (platforms/qt-desktop: fixtures, differential, CLI, GUI offscreen)"
  if command -v qmake6 >/dev/null 2>&1; then
    ( cd "$ROOT/platforms/qt-desktop" && cmake -S . -B "$ROOT/build/qt" -G Ninja >/dev/null && cmake --build "$ROOT/build/qt" >/dev/null && ctest --test-dir "$ROOT/build/qt" ) > "$ROOT/build/qt-test.log" 2>&1
  else
    docker run --rm --user "$(id -u):$(id -g)" -v "$ROOT":/repo -w /repo/platforms/qt-desktop uztranslit-qt \
      sh -c 'cmake -S . -B /repo/build/qt -G Ninja >/dev/null && cmake --build /repo/build/qt >/dev/null && ctest --test-dir /repo/build/qt' > "$ROOT/build/qt-test.log" 2>&1
  fi && grep "tests passed" "$ROOT/build/qt-test.log" || { tail -30 "$ROOT/build/qt-test.log"; fail=1; }
else
  echo "== Qt 6 not available (no qmake6, no uztranslit-qt image): desktop skipped"
fi
if [ -n "${GITHUB_ACTIONS:-}" ]; then
  echo "== Android, Swift and Qt suites: run by their own workflows in CI"
elif [ -n "${JAVA_HOME:-}" ] && { [ -n "${ANDROID_HOME:-}" ] || [ -f "$ROOT/platforms/android/local.properties" ]; }; then
  echo "== Kotlin core + Android app (platforms/android: fixtures, differential, unit tests)"
  ( cd "$ROOT/platforms/android" && ./gradlew --no-daemon -q test ) > "$ROOT/build/android-test.log" 2>&1 && echo "gradle test: ok" || { tail -30 "$ROOT/build/android-test.log"; fail=1; }
else
  echo "== Android SDK or JDK not configured (JAVA_HOME, ANDROID_HOME): Kotlin core skipped"
fi
if [ -n "${GITHUB_ACTIONS:-}" ]; then :
elif command -v swift >/dev/null 2>&1 || docker image inspect swift:6.4.1-noble >/dev/null 2>&1; then
  echo "== Swift core (platforms/ios: fixtures + differential)"
  if "$ROOT/platforms/ios/scripts/test.sh" > "$ROOT/build/swift-test.log" 2>&1; then
    grep -E "^(212|differential)" "$ROOT/build/swift-test.log"
  else
    tail -30 "$ROOT/build/swift-test.log"; fail=1
  fi
else
  echo "== Swift not available (no swift, no swift:6.4.1-noble image): Swift core skipped"
fi
echo "== Web engine (fixtures through both engine builds, every document format; LibreOffice round-trips when installed)"
( cd "$ROOT/web" &&
  { [ -d node_modules ] || npm ci --no-audit --no-fund --silent; } &&
  npm run --silent test:engine ) || fail=1
[ $fail -eq 0 ] && echo "ALL SUITES GREEN" || { echo "FAILURES"; exit 1; }
