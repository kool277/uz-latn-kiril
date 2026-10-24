#!/usr/bin/env bash
# Builds UzTranslit-<version>-macOS.dmg from a configured and built tree: macdeployqt copies Qt into UzTranslit.app,
# the bundle is signed ad hoc (unsigned arm64 code does not run at all) and hdiutil writes a compressed disk image
# with an Applications link to drag the app onto.
#   platforms/qt-desktop/packaging/macos/build-dmg.sh [build-dir]
# Needs Qt's macdeployqt on PATH (or MACDEPLOYQT=/path/to/macdeployqt). The image is not notarized: the first launch
# needs right-click ▸ Open (or System Settings ▸ Privacy & Security ▸ Open Anyway).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$(cd "$HERE/../.." && pwd)"
BUILD="$(cd "${1:-$PROJECT/build}" && pwd)"
VERSION="$(sed -n 's/^CMAKE_PROJECT_VERSION:STATIC=//p' "$BUILD/CMakeCache.txt")"
APP="$BUILD/UzTranslit.app"
[ -d "$APP" ] || { echo "$APP not found: build the project first" >&2; exit 1; }

MACDEPLOYQT="${MACDEPLOYQT:-$(command -v macdeployqt || command -v macdeployqt6 || true)}"
[ -n "$MACDEPLOYQT" ] || { echo "macdeployqt not found: set MACDEPLOYQT" >&2; exit 1; }
"$MACDEPLOYQT" "$APP" -always-overwrite
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"

STAGE="$BUILD/dmg-stage"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
DMG="$BUILD/UzTranslit-$VERSION-macOS.dmg"
rm -f "$DMG"
hdiutil create -volname "UzTranslit $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG"
rm -rf "$STAGE"
echo "built $DMG"
