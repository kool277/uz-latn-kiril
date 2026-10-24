#!/usr/bin/env bash
# Copies the conformance data into the Swift package's test resources (the copies are gitignored; never hand-copy
# cases): spec/fixtures.json always, build/differential.json when it exists (node tools/make_differential.mjs).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
DEST="$HERE/../UzTranslitCore/Tests/UzTranslitCoreTests/Resources"
mkdir -p "$DEST"
cp "$ROOT/spec/fixtures.json" "$DEST/fixtures.json"
echo "synced spec/fixtures.json"
if [ -f "$ROOT/build/differential.json" ]; then
  cp "$ROOT/build/differential.json" "$DEST/differential.json"
  echo "synced build/differential.json"
else
  rm -f "$DEST/differential.json"
  echo "no build/differential.json (run: node tools/make_differential.mjs) — DifferentialTests will be skipped"
fi
