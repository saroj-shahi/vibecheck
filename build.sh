#!/bin/bash
# Builds VibeCheck.app into ./build. Usage: ./build.sh [--install]  (--install copies it to /Applications)
# Builds for this Mac's architecture only. VIBECHECK_ARCHS="arm64 x86_64" makes a universal app that runs on
# Apple silicon and Intel Macs (scripts/release.sh sets it).
set -euo pipefail
cd "$(dirname "$0")"

read -r -a ARCHS <<< "${VIBECHECK_ARCHS:-$(uname -m)}"
# Where SwiftPM puts a release build differs between toolchains (per-architecture folders, or one shared
# folder that each --arch build overwrites), so ask it, and copy each architecture's binaries aside right
# after building them. Resources (strings) are the same for every architecture, so they come from the first.
bin_path() { swift build -c release --arch "$1" --show-bin-path; }
products() { echo ".build/archs/$1"; }
FIRST="$(bin_path "${ARCHS[0]}")"
# Copies one built executable into the app, merging the architectures with lipo when there are several.
install_binary() { # $1: product name, $2: destination
  local inputs=() arch
  for arch in "${ARCHS[@]}"; do inputs+=("$(products "$arch")/$1"); done
  if [ "${#inputs[@]}" = 1 ]; then cp "${inputs[0]}" "$2"; else lipo -create "${inputs[@]}" -output "$2"; fi
}

# App Intents (Shortcuts/Spotlight actions) need metadata that Xcode normally generates: the compiler writes
# the intents' constant values, then appintentsmetadataprocessor turns them into Metadata.appintents.
INTENTS=.build/intents
mkdir -p "$INTENTS"
echo '["AppIntent","EntityQuery","AppEntity","TransientEntity","AppEnum","AppShortcutProviding","AppShortcutsProvider","AnyResolverProviding","AppIntentsPackage","DynamicOptionsProvider","IntentValueQuery","Resolver","AppExtension","ExtensionPointDefining","_IntentValueRepresentable","_AssistantIntentsProvider"]' > "$INTENTS/protocols.json"
build_release() {
  local arch
  for arch in "${ARCHS[@]}"; do
    # The const values don't depend on the architecture, so each build may overwrite the same file.
    # Every module compiled with these flags writes to that one path and the last one wins, so only the app's
    # product gets them; the widget and the CLI build separately without (else the CLI can overwrite them with []).
    swift build -c release --arch "$arch" --product VibeCheck \
      -Xswiftc -emit-const-values-path -Xswiftc "$PWD/$INTENTS/VibeCheck.swiftconstvalues" \
      -Xswiftc -Xfrontend -Xswiftc -const-gather-protocols-file -Xswiftc -Xfrontend -Xswiftc "$PWD/$INTENTS/protocols.json"
    swift build -c release --arch "$arch" --product VibeCheckWidget
    swift build -c release --arch "$arch" --product VibeCheckCLI
    mkdir -p "$(products "$arch")"
    cp "$(bin_path "$arch")/VibeCheck" "$(bin_path "$arch")/VibeCheckWidget" "$(bin_path "$arch")/VibeCheckCLI" "$(products "$arch")/"
  done
}
build_release
# A no-op incremental build leaves the const values empty ("[]"), and the metadata step below then fails.
# Touching a source file makes the module recompile and write them again.
if [ "$(wc -c < "$INTENTS/VibeCheck.swiftconstvalues" 2>/dev/null || echo 0)" -lt 16 ]; then
  touch Sources/VibeCheck/App/Intents.swift
  build_release
fi
APP=build/VibeCheck.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
install_binary VibeCheck "$APP/Contents/MacOS/VibeCheck"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# The `vibecheck` command line tool (Homebrew links it onto PATH). Named VibeCheckCLI while building because
# "vibecheck" would collide with the app binary on a case-insensitive disk.
mkdir -p "$APP/Contents/Helpers"
install_binary VibeCheckCLI "$APP/Contents/Helpers/vibecheck"

# Strings: compile Sources/VibeCheck/Resources/Localizable.xcstrings into <language>.lproj folders inside the
# SwiftPM resource bundle (`swift build` only copies the catalog). SwiftUI's Text("…") and String(localized:) look
# in the main bundle, so copy them there.
scripts/compile_strings.sh "$FIRST/VibeCheck_VibeCheck.bundle"
LPROJ_FOUND=0
for lproj in "$FIRST"/VibeCheck_VibeCheck.bundle/Contents/Resources/*.lproj "$FIRST"/VibeCheck_VibeCheck.bundle/*.lproj; do
  [ -d "$lproj" ] || continue
  cp -R "$lproj" "$APP/Contents/Resources/"
  LPROJ_FOUND=1
done
[ "$LPROJ_FOUND" = 1 ] || { echo "error: compiled strings (*.lproj) missing from the SwiftPM resource bundle" >&2; exit 1; }

# App Shortcut phrases: the system reads <language>.lproj/AppShortcuts.strings from the app's own Resources.
SHORTCUTS_OUT="$(mktemp -d)"
xcrun xcstringstool compile Sources/VibeCheck/Resources/AppShortcuts.xcstrings --output-directory "$SHORTCUTS_OUT"
for lproj in "$SHORTCUTS_OUT"/*.lproj; do
  [ -f "$lproj/AppShortcuts.strings" ] || continue
  mkdir -p "$APP/Contents/Resources/$(basename "$lproj")"
  cp "$lproj/AppShortcuts.strings" "$APP/Contents/Resources/$(basename "$lproj")/"
done
ls "$APP"/Contents/Resources/*.lproj/AppShortcuts.strings >/dev/null 2>&1 || { echo "error: AppShortcuts.strings missing" >&2; exit 1; }
rm -rf "$SHORTCUTS_OUT"

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

# Assets.car: the Liquid Glass icon (macOS 26+; CFBundleIconName in Info.plist points at it, macOS 14-15 keep
# using AppIcon.icns above) and the vibe ring's custom SF Symbols (Resources/Symbols.xcassets, written by
# scripts/render_ring_symbol.swift). Without it the ring falls back to drawn shapes.
ICON_OUT="$(mktemp -d)"
if xcrun actool branding/VibeCheck.icon Resources/Symbols.xcassets --compile "$ICON_OUT" --app-icon VibeCheck --platform macosx \
     --minimum-deployment-target 14.0 --output-partial-info-plist "$ICON_OUT/partial.plist" \
     --enable-on-demand-resources NO >/dev/null 2>&1 && [ -f "$ICON_OUT/Assets.car" ]; then
  cp "$ICON_OUT/Assets.car" "$APP/Contents/Resources/Assets.car"
else
  echo "warning: actool could not compile branding/VibeCheck.icon and Resources/Symbols.xcassets; using the flat icon and the drawn ring" >&2
  /usr/libexec/PlistBuddy -c "Delete :CFBundleIconName" "$APP/Contents/Info.plist" 2>/dev/null || true
fi

# Signing identity, best first (override with VIBECHECK_SIGN_IDENTITY):
# 1. "Apple Development: …" (free with an Apple ID in Xcode). It carries a Team ID, and Keychain
#    "Always Allow" on another app's item is recorded per team, so it survives updates.
# 2. "VibeCheck Local Signing" (self-signed). Stable identity, but no Team ID: Keychain records the exact
#    build (cdhash), so macOS asks again after every update.
# 3. Ad hoc.
# Releases use "Developer ID Application: …" (scripts/release.sh passes it in VIBECHECK_SIGN_IDENTITY): same
# Team ID path as Apple Development, plus the hardened runtime and a secure timestamp, which notarization needs.
# VIBECHECK_HARDENED=1 turns the hardened runtime on with any identity, to test it before a release.
IDENTITIES=$(security find-identity -v -p codesigning)
DEVELOPMENT=$(printf '%s\n' "$IDENTITIES" | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' | head -1)
IDENTITY="${VIBECHECK_SIGN_IDENTITY:-${DEVELOPMENT:-VibeCheck Local Signing}}"
SIGN_FLAGS=()
if [[ "$IDENTITY" == "Developer ID Application:"* || "${VIBECHECK_HARDENED:-0}" = 1 ]]; then
  SIGN_FLAGS=(--options runtime --timestamp)
fi
if printf '%s\n' "$IDENTITIES" | grep -qF "\"$IDENTITY\""; then
  # Inside-out: the helper is signed before the app's final signature seals it (hardened runtime when the app has it).
  codesign --force "${SIGN_FLAGS[@]+"${SIGN_FLAGS[@]}"}" --sign "$IDENTITY" --identifier io.github.saroj-shahi.vibecheck.cli "$APP/Contents/Helpers/vibecheck"
  # Widgets: the extension must be sandboxed and shares the app group "<Team ID>.io.github.saroj-shahi.vibecheck" with the
  # app, so it needs a Team ID; with other identities the app ships without widgets.
  if [[ "$IDENTITY" == "Apple Development:"* || "$IDENTITY" == "Developer ID Application:"* ]]; then
    APPEX="$APP/Contents/PlugIns/VibeCheckWidget.appex"
    mkdir -p "$APPEX/Contents/MacOS"
    install_binary VibeCheckWidget "$APPEX/Contents/MacOS/VibeCheckWidget"
    cp Resources/Widget/Info.plist "$APPEX/Contents/Info.plist"
    for key in CFBundleShortVersionString CFBundleVersion; do
      /usr/libexec/PlistBuddy -c "Set :$key $(/usr/libexec/PlistBuddy -c "Print :$key" "$APP/Contents/Info.plist")" "$APPEX/Contents/Info.plist"
    done
    mkdir -p "$APPEX/Contents/Resources"
    cp -R "$APP/Contents/Resources/"*.lproj "$APPEX/Contents/Resources/"
    codesign --force "${SIGN_FLAGS[@]+"${SIGN_FLAGS[@]}"}" --sign "$IDENTITY" --entitlements Resources/Widget/Widget.entitlements "$APPEX"
    codesign --force "${SIGN_FLAGS[@]+"${SIGN_FLAGS[@]}"}" --sign "$IDENTITY" --entitlements Resources/VibeCheck.entitlements "$APP"
    CERT_TEAM=$(codesign -dv "$APP" 2>&1 | sed -n 's/^TeamIdentifier=//p' | head -1)
    ENT_GROUP=$(/usr/libexec/PlistBuddy -c "Print :com.apple.security.application-groups:0" Resources/VibeCheck.entitlements 2>/dev/null || true)
    ENT_TEAM="${ENT_GROUP%%.*}"
    if [ -n "$CERT_TEAM" ] && [ "$CERT_TEAM" != "not set" ] && [ -n "$ENT_TEAM" ] && [ "$CERT_TEAM" != "$ENT_TEAM" ]; then
      echo "warning: signing Team ID ($CERT_TEAM) differs from entitlements app group prefix ($ENT_TEAM); update Resources/{VibeCheck,Widget/Widget}.entitlements and Sources/VibeCheckShared/WidgetSnapshot.swift for widgets to share state" >&2
    fi
  else
    echo "warning: \"$IDENTITY\" has no Team ID; building without widgets" >&2
    codesign --force --sign "$IDENTITY" "$APP"
  fi
  echo "Signed with \"$IDENTITY\"${SIGN_FLAGS[*]+ (${SIGN_FLAGS[*]})}"
else
  codesign --force --sign - "$APP/Contents/Helpers/vibecheck"
  codesign --force --sign - "$APP"
  echo "Signed ad hoc (no \"$IDENTITY\" certificate)"
fi
codesign --verify --deep --strict "$APP"
echo "Verified the signature"
echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/VibeCheck"))"

if [ "${1:-}" = "--install" ]; then
  rm -rf /Applications/VibeCheck.app
  cp -R "$APP" /Applications/
  echo "Installed to /Applications/VibeCheck.app"
fi
