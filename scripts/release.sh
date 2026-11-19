#!/bin/bash
# Builds a VibeCheck release anyone can install: Developer ID signed, notarized and stapled, in a DMG.
#
#   scripts/release.sh            full release: build, notarize the app, DMG, notarize the DMG, staple, check
#   scripts/release.sh --dry-run  same steps without a Developer ID or notarization (signs with whatever
#                                 build.sh picks, hardened runtime on), to test the pipeline and the DMG
#
# One-time setup (needs a paid Apple Developer Program membership):
#   1. Xcode → Settings → Accounts → Manage Certificates → + → "Developer ID Application".
#   2. Store notary credentials in the Keychain (an app-specific password from account.apple.com):
#        xcrun notarytool store-credentials vibecheck-notary --apple-id <apple id> --team-id <team id>
#   Override with VIBECHECK_SIGN_IDENTITY (the full "Developer ID Application: …" name) and
#   VIBECHECK_NOTARY_PROFILE (the keychain profile name, default vibecheck-notary).
#
# Output: build/release/VibeCheck-<version>.dmg and its .sha256. Publishing is left to you (see the end).
set -euo pipefail
cd "$(dirname "$0")/.."

DRY_RUN=0
case "${1:-}" in
  "") ;;
  --dry-run) DRY_RUN=1 ;;
  *) echo "usage: scripts/release.sh [--dry-run]" >&2; exit 2 ;;
esac
PROFILE="${VIBECHECK_NOTARY_PROFILE:-vibecheck-notary}"
APP=build/VibeCheck.app
OUT=build/release
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Resources/Info.plist)
DMG="$OUT/VibeCheck-$VERSION.dmg"

step() { printf '\n==> %s\n' "$*"; }
die() { echo "error: $*" >&2; exit 1; }

# The Team ID baked into the app group entitlement; the signing certificate must belong to the same team or the
# widget can't read the app's snapshot.
GROUP_TEAM=$(/usr/libexec/PlistBuddy -c "Print :com.apple.security.application-groups:0" Resources/VibeCheck.entitlements | cut -d. -f1)

if [ "$DRY_RUN" = 0 ]; then
  IDENTITY="${VIBECHECK_SIGN_IDENTITY:-$(security find-identity -v -p codesigning \
    | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)}"
  [ -n "$IDENTITY" ] || die "no \"Developer ID Application\" certificate in the keychain (see the setup notes at the top of this script), or run with --dry-run"
  CERT_TEAM=$(printf '%s' "$IDENTITY" | sed -n 's/.*(\([A-Z0-9]*\))$/\1/p')
  [ "$CERT_TEAM" = "$GROUP_TEAM" ] || die "certificate team ($CERT_TEAM) doesn't match the app group team ($GROUP_TEAM) in Resources/*.entitlements"
  xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1 \
    || die "notary profile \"$PROFILE\" not found or not working; run: xcrun notarytool store-credentials $PROFILE --apple-id <apple id> --team-id $GROUP_TEAM"
  export VIBECHECK_SIGN_IDENTITY="$IDENTITY"
else
  export VIBECHECK_HARDENED=1
  echo "Dry run: no Developer ID, no notarization. The DMG works on this Mac only; Gatekeeper will reject it elsewhere."
fi

notarize() { # $1: file to submit (zip or dmg)
  xcrun notarytool submit "$1" --keychain-profile "$PROFILE" --wait --output-format json > "$OUT/notary.json" || true
  local status id
  status=$(/usr/bin/plutil -extract status raw "$OUT/notary.json" 2>/dev/null || echo unknown)
  id=$(/usr/bin/plutil -extract id raw "$OUT/notary.json" 2>/dev/null || echo "")
  if [ "$status" != "Accepted" ]; then
    [ -n "$id" ] && xcrun notarytool log "$id" --keychain-profile "$PROFILE" >&2 || cat "$OUT/notary.json" >&2
    die "notarization of $1 ended with status: $status"
  fi
  echo "Notarized ($id)"
}

step "Building VibeCheck $VERSION ($BUILD_NUMBER)"
./build.sh
rm -rf "$OUT" && mkdir -p "$OUT"

step "Checking the signature"
codesign --verify --deep --strict --verbose=2 "$APP"
[[ "$(codesign -dv "$APP" 2>&1)" == *"(runtime)"* ]] || die "hardened runtime is off"
[ -d "$APP/Contents/PlugIns/VibeCheckWidget.appex" ] || echo "warning: no widget extension in this build" >&2

if [ "$DRY_RUN" = 0 ]; then
  step "Notarizing the app"
  ditto -c -k --keepParent "$APP" "$OUT/VibeCheck.zip"
  notarize "$OUT/VibeCheck.zip"
  rm "$OUT/VibeCheck.zip"
  xcrun stapler staple "$APP"
fi

step "Making the DMG"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/VibeCheck.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "VibeCheck $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
if [ "$DRY_RUN" = 0 ]; then
  codesign --force --timestamp --sign "$IDENTITY" "$DMG"
  step "Notarizing the DMG"
  notarize "$DMG"
  xcrun stapler staple "$DMG"
  step "Gatekeeper check"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
  xcrun stapler validate "$DMG"
fi
rm -f "$OUT/notary.json"
(cd "$OUT" && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")

step "Done: $DMG"
cat "$DMG.sha256"
if [ "$DRY_RUN" = 0 ]; then
  cat <<EOF

To publish (the app's update check reads the latest GitHub release; the tag must be v$VERSION):
  git tag v$VERSION && git push origin v$VERSION
  gh release create v$VERSION "$DMG" --title "VibeCheck $VERSION" --notes "…"
EOF
fi
