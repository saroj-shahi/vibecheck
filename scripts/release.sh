#!/bin/bash
# Builds a VibeCheck release anyone can install: Developer ID signed, notarized and stapled, in a DMG.
#
#   scripts/release.sh            full release: build, notarize the app, DMG, notarize the DMG, staple, check
#   scripts/release.sh --share    DMG for colleagues, no Developer ID needed: signed with the Apple Development
#                                 identity (widgets work), not notarized, with a "How to open" note inside.
#                                 Each person runs `xattr -dr com.apple.quarantine` on the app once (Open Anyway
#                                 is unreliable for un-notarized apps on recent macOS).
#   scripts/release.sh --dry-run  same as --share; kept as an alias
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
  --share|--dry-run) DRY_RUN=1 ;;
  *) echo "usage: scripts/release.sh [--share]" >&2; exit 2 ;;
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
  [ -n "$IDENTITY" ] || die "no \"Developer ID Application\" certificate in the keychain (see the setup notes at the top of this script), or run with --share to make a DMG for colleagues"
  CERT_TEAM=$(printf '%s' "$IDENTITY" | sed -n 's/.*(\([A-Z0-9]*\))$/\1/p')
  [ "$CERT_TEAM" = "$GROUP_TEAM" ] || die "certificate team ($CERT_TEAM) doesn't match the app group team ($GROUP_TEAM) in Resources/*.entitlements"
  xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1 \
    || die "notary profile \"$PROFILE\" not found or not working; run: xcrun notarytool store-credentials $PROFILE --apple-id <apple id> --team-id $GROUP_TEAM"
  export VIBECHECK_SIGN_IDENTITY="$IDENTITY"
else
  export VIBECHECK_HARDENED=1
  echo "Share build: no Developer ID, not notarized. On other Macs, macOS blocks it until the person clears the quarantine"
  echo "flag with one Terminal command (the DMG includes a note saying how)."
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
if [ "$DRY_RUN" = 1 ]; then
  cat > "$STAGE/How to open.txt" <<NOTE
VibeCheck $VERSION: how to install and open it

1. Drag VibeCheck into the Applications folder (in this window).
2. Open Terminal (Applications → Utilities → Terminal), paste this line and press Return:

     xattr -dr com.apple.quarantine /Applications/VibeCheck.app

3. Open VibeCheck from Applications. It lives in the menu bar (top right of the screen).

Why step 2: VibeCheck is shared directly, not through the App Store, and isn't notarized by Apple,
so macOS blocks it until you clear the "downloaded from the internet" flag. You only do this once
per version. (System Settings → Privacy & Security → "Open Anyway" may also work, but on recent
macOS versions it often doesn't for apps like this.)

Updating: quit VibeCheck, drag the new version into Applications, replace the old one, and run
step 2 again. Your settings are kept. Needs macOS 14 or later.
NOTE
fi
# The install window: branded background (scripts/render_dmg.swift), the app icon on the volume, and the icons
# placed on the art by Finder. Positions match the layout constants in render_dmg.swift.
ART=share; [ "$DRY_RUN" = 0 ] && ART=release
mkdir "$STAGE/.background"
tiffutil -cathidpicheck "branding/dmg/$ART.png" "branding/dmg/$ART@2x.png" -out "$STAGE/.background/background.tiff" 2>/dev/null
VOLNAME="VibeCheck $VERSION"
MOUNT="/Volumes/$VOLNAME"
[ -d "$MOUNT" ] && hdiutil detach -quiet "$MOUNT" -force || true
RW="$OUT/VibeCheck-rw.dmg"
hdiutil create -quiet -volname "$VOLNAME" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$RW"
hdiutil attach -quiet -readwrite -noverify -noautoopen -mountpoint "$MOUNT" "$RW"
NOTE_POSITION=""
[ "$DRY_RUN" = 1 ] && NOTE_POSITION='set position of item "How to open.txt" to {572, 390}'
# Finder needs Automation permission for Terminal (asked once). Without it the DMG still works, just plain.
if ! osascript >/dev/null <<APPLESCRIPT
tell application "Finder"
  tell disk "$VOLNAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {160, 120, 846, 652}
    set opts to icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 100
    set text size of opts to 13
    set background picture of opts to file ".background:background.tiff"
    set position of item "VibeCheck.app" to {180, 222}
    set position of item "Applications" to {500, 222}
    $NOTE_POSITION
    update without registering applications
    -- Leave the window open: about 5 s after it closes, Finder (macOS 26+) rewrites .DS_Store with its
    -- default view settings. The disk is detached with the window still open instead.
  end tell
end tell
APPLESCRIPT
then
  echo "warning: Finder couldn't lay out the DMG window (allow Terminal to control Finder in System Settings → Privacy & Security → Automation); the DMG is plain" >&2
fi
# Wait until Finder has written the layout (background picture + icon size) to .DS_Store, or the finished DMG
# opens as a plain window.
dsstore_ok() { # $1: volume root
  python3 -I - "$1/.DS_Store" <<'PY'
import plistlib, struct, sys
try:
    data = open(sys.argv[1], "rb").read()
except OSError:
    sys.exit(1)
i = data.find(b"icvpblob")
if i < 0:
    sys.exit(1)
size = struct.unpack(">I", data[i + 8:i + 12])[0]
view = plistlib.loads(data[i + 12:i + 12 + size])
print(f"backgroundType={view.get('backgroundType')} iconSize={view.get('iconSize')}", file=sys.stderr)
sys.exit(0 if view.get("backgroundType") == 2 and view.get("iconSize") == 100 else 1)
PY
}
# Finder may write more than once, so the layout must still be there a few seconds after it first shows up.
STABLE=0
for _ in $(seq 1 30); do
  if dsstore_ok "$MOUNT" 2>/dev/null; then STABLE=$((STABLE + 1)); else STABLE=0; fi
  [ "$STABLE" -ge 4 ] && break
  sleep 1
done
[ "$STABLE" -ge 4 ] || { echo "warning: Finder didn't save the window layout:" >&2; dsstore_ok "$MOUNT" || true; }
# The disk's own icon goes on last: Finder's "update" deletes .VolumeIcon.icns and clears the custom-icon flag
# (and hdiutil -srcfolder leaves the file out).
cp Resources/AppIcon.icns "$MOUNT/.VolumeIcon.icns"
SetFile -a C "$MOUNT" 2>/dev/null || echo "warning: couldn't set the volume icon (SetFile)" >&2
sync
hdiutil detach -quiet "$MOUNT" || { sleep 2; hdiutil detach -quiet -force "$MOUNT"; }
hdiutil convert -quiet "$RW" -format UDZO -imagekey zlib-level=9 -ov -o "$DMG"
rm -f "$RW"
# Check the finished DMG itself, mounted out of Finder's sight.
CHECK=$(mktemp -d)
hdiutil attach -quiet -readonly -nobrowse -noautoopen -mountpoint "$CHECK" "$DMG"
if dsstore_ok "$CHECK" 2>/dev/null; then echo "Install window: background and layout saved in the DMG"
else echo "warning: the DMG's install window will look plain:" >&2; dsstore_ok "$CHECK" || true; fi
hdiutil detach -quiet "$CHECK"; rmdir "$CHECK"
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

# Same file under a fixed name: the README's download button links to releases/latest/download/VibeCheck.dmg.
cp -f "$DMG" "$OUT/VibeCheck.dmg"

step "Done: $DMG"
cat "$DMG.sha256"
cat <<EOF

To publish (the app's update check and the README's download button read the latest GitHub release;
the tag must be v$VERSION and the release must carry VibeCheck.dmg):
  git tag v$VERSION && git push origin v$VERSION
  gh release create v$VERSION "$OUT/VibeCheck.dmg" "$DMG" --title "VibeCheck $VERSION" --notes "…"
EOF
