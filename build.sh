#!/bin/bash
# Builds VibeCheck.app into ./build. Usage: ./build.sh [--install]  (--install copies it to /Applications)
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
APP=build/VibeCheck.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/VibeCheck "$APP/Contents/MacOS/VibeCheck"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# The icon is rendered from branding/svg by scripts/render_brand.swift and committed.
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - "$APP"
echo "Built $APP"

if [ "${1:-}" = "--install" ]; then
  rm -rf /Applications/VibeCheck.app
  cp -R "$APP" /Applications/
  echo "Installed to /Applications/VibeCheck.app"
fi
