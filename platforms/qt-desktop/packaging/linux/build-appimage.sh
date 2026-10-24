#!/usr/bin/env bash
# Builds UzTranslit-<version>-x86_64.AppImage from a configured and built tree (linuxdeploy + its Qt plugin).
#   platforms/qt-desktop/packaging/linux/build-appimage.sh [build-dir]
# Needs: the build tree (cmake --build), Qt's qmake on PATH (or QMAKE=/path/to/qmake), and curl, or
# LINUXDEPLOY_DIR pointing to linuxdeploy-x86_64.AppImage and linuxdeploy-plugin-qt-x86_64.AppImage.
# The X11 platform plugin's system libraries (libxcb-cursor0 & co.) must be installed so that they get bundled.
# The AppImage runs on distributions with a glibc at least as new as the build machine's.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$(cd "$HERE/../.." && pwd)"
BUILD="$(cd "${1:-$PROJECT/build}" && pwd)"
VERSION="$(sed -n 's/^CMAKE_PROJECT_VERSION:STATIC=//p' "$BUILD/CMakeCache.txt")"
ARCH=x86_64
TOOLS="${LINUXDEPLOY_DIR:-$BUILD/tools}"

# pinned releases and their SHA-256 sums
LINUXDEPLOY_URL=https://github.com/linuxdeploy/linuxdeploy/releases/download/1-alpha-20251107-1/linuxdeploy-x86_64.AppImage
LINUXDEPLOY_SHA256=c20cd71e3a4e3b80c3483cef793cda3f4e990aca14014d23c544ca3ce1270b4d
PLUGIN_QT_URL=https://github.com/linuxdeploy/linuxdeploy-plugin-qt/releases/download/1-alpha-20250213-1/linuxdeploy-plugin-qt-x86_64.AppImage
PLUGIN_QT_SHA256=15106be885c1c48a021198e7e1e9a48ce9d02a86dd0a1848f00bdbf3c1c92724

fetch() { # url sha256 → $TOOLS/<file name>, verified
    local url=$1 sum=$2 file
    file="$TOOLS/$(basename "$url")"
    if [ ! -f "$file" ]; then
        mkdir -p "$TOOLS"
        curl -fsSL --retry 3 -o "$file.part" "$url"
        mv "$file.part" "$file"
    fi
    echo "$sum  $file" | sha256sum -c --quiet - || { echo "checksum mismatch: $file" >&2; exit 1; }
    chmod +x "$file"
}
fetch "$LINUXDEPLOY_URL" "$LINUXDEPLOY_SHA256"
fetch "$PLUGIN_QT_URL" "$PLUGIN_QT_SHA256"

APPDIR="$BUILD/AppDir"
rm -rf "$APPDIR"
DESTDIR="$APPDIR" cmake --install "$BUILD" --prefix /usr

export QMAKE="${QMAKE:-$(command -v qmake6 || command -v qmake || true)}"
[ -n "$QMAKE" ] || { echo "qmake not found: set QMAKE" >&2; exit 1; }
export APPIMAGE_EXTRACT_AND_RUN=1 # no FUSE needed (containers, CI)
export NO_STRIP=1                 # linuxdeploy's own strip is older than current toolchains
export LDAI_OUTPUT="UzTranslit-$VERSION-$ARCH.AppImage"
export OUTPUT="$LDAI_OUTPUT"

cd "$BUILD"
"$TOOLS/linuxdeploy-x86_64.AppImage" \
    --appdir "$APPDIR" \
    --executable "$APPDIR/usr/bin/uztranslit" \
    --desktop-file "$APPDIR/usr/share/applications/uztranslit.desktop" \
    --icon-file "$APPDIR/usr/share/icons/hicolor/256x256/apps/uztranslit.png" \
    --plugin qt \
    --output appimage
echo "built $BUILD/$OUTPUT"
