#!/usr/bin/env bash
# Runs the Swift package tests: differential corpus (when node is available), test data sync, swift test.
# Uses the local Swift toolchain, or the official Swift Docker image when `swift` is not installed.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
SWIFT_IMAGE="${SWIFT_IMAGE:-swift:6.4.1-noble}"

if command -v node >/dev/null 2>&1; then
  node "$ROOT/tools/make_differential.mjs"
else
  echo "node not found: using the existing build/differential.json, if any"
fi
"$HERE/sync-fixtures.sh"

if command -v swift >/dev/null 2>&1; then
  cd "$HERE/../UzTranslitCore" && swift test
elif command -v docker >/dev/null 2>&1; then
  docker run --rm -v "$ROOT":/repo -w /repo/platforms/ios/UzTranslitCore --user "$(id -u):$(id -g)" -e HOME=/tmp \
    "$SWIFT_IMAGE" swift test
else
  echo "neither swift nor docker is installed" >&2
  exit 1
fi
