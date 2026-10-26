#!/usr/bin/env bash
# Starts a release APK on a running emulator or device and checks that it works after R8 shrinking: shares
# "Toshkent shahri" to the app (default target: Yangi lotin) and expects "Toşkent şahri" on the screen, with no crash.
# usage: platforms/android/scripts/smoke-test.sh app-release.apk      (CI: android.yml, on an emulator)
set -euo pipefail
apk="$1"
pkg=uz.jaybi.uztranslit
out="${TMPDIR:-/tmp}/uzt-smoke"
mkdir -p "$out"

adb wait-for-device
adb install -r "$apk"
adb logcat -c
adb shell am start -W -a android.intent.action.SEND -t text/plain \
  --es android.intent.extra.TEXT "'Toshkent shahri'" -n "$pkg/.MainActivity"

found=""
for _ in $(seq 1 20); do
  sleep 2
  adb shell uiautomator dump /sdcard/uzt-ui.xml > /dev/null 2>&1 || continue
  adb exec-out cat /sdcard/uzt-ui.xml > "$out/ui.xml"
  if grep -q "Toşkent şahri" "$out/ui.xml"; then found=1; break; fi
done
adb logcat -d -b crash > "$out/crash.txt" || true
adb logcat -d > "$out/logcat.txt" || true

if grep -q "$pkg" "$out/crash.txt"; then
  echo "FAIL: the app crashed"; cat "$out/crash.txt"; exit 1
fi
if [ -z "$(adb shell pidof "$pkg" | tr -d '\r')" ]; then
  echo "FAIL: the app is not running"; grep -E "AndroidRuntime|$pkg" "$out/logcat.txt" | tail -40; exit 1
fi
if [ -z "$found" ]; then
  echo "FAIL: 'Toşkent şahri' not on the screen"; grep -o 'text="[^"]*"' "$out/ui.xml" | head -40; exit 1
fi
echo "smoke test passed: shared text converted on screen, no crash"
