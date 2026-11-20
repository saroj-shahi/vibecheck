#!/bin/bash
# Compiles Sources/VibeCheck/Resources/Localizable.xcstrings into <language>.lproj/Localizable.strings inside a
# SwiftPM resource bundle. Usage: scripts/compile_strings.sh <path to VibeCheck_VibeCheck.bundle>
# `swift build` (the native build system) only copies .xcstrings into the bundle; Foundation can't read that, so
# Bundle.module and the app would fall back to the raw keys. Xcode's build system compiles it, so a bundle that
# already has .lproj folders is left alone.
set -euo pipefail
cd "$(dirname "$0")/.."

BUNDLE="${1:?usage: $0 <resource bundle>}"
CATALOG=Sources/VibeCheck/Resources/Localizable.xcstrings
[ -d "$BUNDLE" ] || { echo "error: $BUNDLE not found; build first" >&2; exit 1; }

for dir in "$BUNDLE"/*.lproj "$BUNDLE"/Contents/Resources/*.lproj; do
  [ -d "$dir" ] && exit 0
done

# Bundles built for macOS by SwiftPM are flat; follow Contents/Resources if this one has it.
OUT="$BUNDLE"
[ -d "$BUNDLE/Contents/Resources" ] && OUT="$BUNDLE/Contents/Resources"
xcrun xcstringstool compile "$CATALOG" --output-directory "$OUT"
ls "$OUT"/*.lproj/Localizable.strings >/dev/null 2>&1 || {
  echo "error: xcstringstool wrote no <language>.lproj/Localizable.strings into $OUT" >&2
  exit 1
}
