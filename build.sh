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

# Sign with a stable identity when one exists, so macOS keeps Keychain "Always Allow" (and other
# permissions) across builds. Ad hoc signatures change every build, so macOS asks again each time.
# Override with VIBECHECK_SIGN_IDENTITY; default is the local self-signed "VibeCheck Local Signing".
IDENTITY="${VIBECHECK_SIGN_IDENTITY:-VibeCheck Local Signing}"
if security find-identity -v -p codesigning | grep -qF "\"$IDENTITY\""; then
  codesign --force --sign "$IDENTITY" "$APP"
  echo "Signed with \"$IDENTITY\""
else
  codesign --force --sign - "$APP"
  echo "Signed ad hoc (no \"$IDENTITY\" certificate; Keychain access is asked again after each build)"
fi
echo "Built $APP"

if [ "${1:-}" = "--install" ]; then
  rm -rf /Applications/VibeCheck.app
  cp -R "$APP" /Applications/
  echo "Installed to /Applications/VibeCheck.app"
fi
