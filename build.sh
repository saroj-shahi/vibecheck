#!/bin/bash
# Builds VibeCheck.app into ./build. Usage: ./build.sh [--install]  (--install copies it to /Applications)
set -euo pipefail
cd "$(dirname "$0")"

# App Intents (Shortcuts/Spotlight actions) need metadata that Xcode normally generates: the compiler writes
# the intents' constant values, then appintentsmetadataprocessor turns them into Metadata.appintents.
INTENTS=.build/intents
mkdir -p "$INTENTS"
echo '["AppIntent","EntityQuery","AppEntity","TransientEntity","AppEnum","AppShortcutProviding","AppShortcutsProvider","AnyResolverProviding","AppIntentsPackage","DynamicOptionsProvider","IntentValueQuery","Resolver","AppExtension","ExtensionPointDefining","_IntentValueRepresentable","_AssistantIntentsProvider"]' > "$INTENTS/protocols.json"
swift build -c release \
  -Xswiftc -emit-const-values-path -Xswiftc "$PWD/$INTENTS/VibeCheck.swiftconstvalues" \
  -Xswiftc -Xfrontend -Xswiftc -const-gather-protocols-file -Xswiftc -Xfrontend -Xswiftc "$PWD/$INTENTS/protocols.json"
APP=build/VibeCheck.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/VibeCheck "$APP/Contents/MacOS/VibeCheck"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Strings: SwiftPM compiles Sources/VibeCheck/Resources/Localizable.xcstrings into <language>.lproj folders inside
# its resource bundle. SwiftUI's Text("…") and String(localized:) look in the main bundle, so copy them there.
LPROJ_FOUND=0
for lproj in .build/release/VibeCheck_VibeCheck.bundle/Contents/Resources/*.lproj .build/release/VibeCheck_VibeCheck.bundle/*.lproj; do
  [ -d "$lproj" ] || continue
  cp -R "$lproj" "$APP/Contents/Resources/"
  LPROJ_FOUND=1
done
[ "$LPROJ_FOUND" = 1 ] || { echo "error: compiled strings (*.lproj) missing from the SwiftPM resource bundle" >&2; exit 1; }

if xcrun --find appintentsmetadataprocessor >/dev/null 2>&1; then
  find "$PWD/Sources/VibeCheck" -name '*.swift' > "$INTENTS/sources.txt"
  echo "$PWD/$INTENTS/VibeCheck.swiftconstvalues" > "$INTENTS/constvals.txt"
  xcrun appintentsmetadataprocessor --output "$APP/Contents/Resources" \
    --toolchain-dir "$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain" --module-name VibeCheck \
    --sdk-root "$(xcrun --sdk macosx --show-sdk-path)" --xcode-version "$(xcodebuild -version | awk '/Build version/{print $3}')" \
    --platform-family macOS --deployment-target 14.0 --target-triple "$(uname -m)-apple-macos14.0" \
    --source-file-list "$INTENTS/sources.txt" --swift-const-vals-list "$INTENTS/constvals.txt" --quiet-warnings 2>&1 \
    | grep -v "Starting App Intents\|Writing Metadata\|Metadata root" || true
  [ -d "$APP/Contents/Resources/Metadata.appintents" ] || { echo "error: App Intents metadata missing" >&2; exit 1; }
else
  echo "warning: Xcode's appintentsmetadataprocessor not found; Shortcuts actions won't show up" >&2
fi

# The icon is rendered from branding/svg by scripts/render_brand.swift and committed.
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Liquid Glass icon (macOS 26+): compile branding/VibeCheck.icon into Assets.car. CFBundleIconName in
# Info.plist points at it; macOS 14-15 keep using AppIcon.icns above. Skipped if actool can't do it.
ICON_OUT="$(mktemp -d)"
if xcrun actool branding/VibeCheck.icon --compile "$ICON_OUT" --app-icon VibeCheck --platform macosx \
     --minimum-deployment-target 14.0 --output-partial-info-plist "$ICON_OUT/partial.plist" \
     --enable-on-demand-resources NO >/dev/null 2>&1 && [ -f "$ICON_OUT/Assets.car" ]; then
  cp "$ICON_OUT/Assets.car" "$APP/Contents/Resources/Assets.car"
else
  echo "warning: actool could not compile branding/VibeCheck.icon; using the flat icon only" >&2
  /usr/libexec/PlistBuddy -c "Delete :CFBundleIconName" "$APP/Contents/Info.plist" 2>/dev/null || true
fi

# Signing identity, best first (override with VIBECHECK_SIGN_IDENTITY):
# 1. "Apple Development: …" (free with an Apple ID in Xcode). It carries a Team ID, and Keychain
#    "Always Allow" on another app's item is recorded per team, so it survives updates.
# 2. "VibeCheck Local Signing" (self-signed). Stable identity, but no Team ID: Keychain records the exact
#    build (cdhash), so macOS asks again after every update.
# 3. Ad hoc.
IDENTITIES=$(security find-identity -v -p codesigning)
DEVELOPMENT=$(printf '%s\n' "$IDENTITIES" | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' | head -1)
IDENTITY="${VIBECHECK_SIGN_IDENTITY:-${DEVELOPMENT:-VibeCheck Local Signing}}"
if printf '%s\n' "$IDENTITIES" | grep -qF "\"$IDENTITY\""; then
  # Widgets: the extension must be sandboxed and shares the app group "<Team ID>.local.vibecheck" with the
  # app, so it needs a Team ID; with other identities the app ships without widgets.
  if [[ "$IDENTITY" == "Apple Development:"* ]]; then
    APPEX="$APP/Contents/PlugIns/VibeCheckWidget.appex"
    mkdir -p "$APPEX/Contents/MacOS"
    cp .build/release/VibeCheckWidget "$APPEX/Contents/MacOS/VibeCheckWidget"
    cp Resources/Widget/Info.plist "$APPEX/Contents/Info.plist"
    for key in CFBundleShortVersionString CFBundleVersion; do
      /usr/libexec/PlistBuddy -c "Set :$key $(/usr/libexec/PlistBuddy -c "Print :$key" "$APP/Contents/Info.plist")" "$APPEX/Contents/Info.plist"
    done
    mkdir -p "$APPEX/Contents/Resources"
    cp -R "$APP/Contents/Resources/"*.lproj "$APPEX/Contents/Resources/"
    codesign --force --sign "$IDENTITY" --entitlements Resources/Widget/Widget.entitlements "$APPEX"
    codesign --force --sign "$IDENTITY" --entitlements Resources/VibeCheck.entitlements "$APP"
  else
    echo "warning: \"$IDENTITY\" has no Team ID; building without widgets" >&2
    codesign --force --sign "$IDENTITY" "$APP"
  fi
  echo "Signed with \"$IDENTITY\""
else
  codesign --force --sign - "$APP"
  echo "Signed ad hoc (no \"$IDENTITY\" certificate)"
fi
echo "Built $APP"

if [ "${1:-}" = "--install" ]; then
  rm -rf /Applications/VibeCheck.app
  cp -R "$APP" /Applications/
  echo "Installed to /Applications/VibeCheck.app"
fi
