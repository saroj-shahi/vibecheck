#!/bin/bash
# Builds a VibeCheck release.
#
#   scripts/release.sh --zip      public GitHub release (the default way to ship): signed with the Apple Development
#                                 identity, hardened runtime, not notarized; build/release/VibeCheck.zip and its
#                                 .sha256, no DMG. People install from Terminal (scripts/install.sh or the Homebrew
#                                 cask in packaging/homebrew), and curl downloads aren't quarantined, so Gatekeeper
#                                 doesn't block it. Prints the cask lines and the tag / gh release commands.
#   scripts/release.sh --publish  --zip, then publish it: tags v<version>, pushes the tag, creates the GitHub release
#                                 with VibeCheck.zip and its .sha256, checks the uploaded zip, and updates
#                                 Casks/vibecheck.rb in saroj-shahi/homebrew-tap from packaging/homebrew/vibecheck.rb.
#                                 Asks before publishing. Needs `gh` signed in with push access to both repos.
#                                 The release stays a draft until its zip is checked. Safe to rerun: a leftover draft
#                                 is replaced; if the release is already public, only the tap is updated (from its
#                                 VibeCheck.zip.sha256), with no rebuild.
#                                 Release notes come from VIBECHECK_RELEASE_NOTES (a file) or GitHub's generated notes.
#   scripts/release.sh            Developer ID release: build, notarize the app, DMG, notarize the DMG, staple, check
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
# Output: build/release/VibeCheck-<version>.dmg and its .sha256 (--zip: VibeCheck.zip and its .sha256).
# Publishing is left to you (see the end).
set -euo pipefail
cd "$(dirname "$0")/.."

DRY_RUN=0
ZIP=0
PUBLISH=0
case "${1:-}" in
  "") ;;
  --share|--dry-run) DRY_RUN=1 ;;
  --zip) DRY_RUN=1; ZIP=1 ;;
  --publish) DRY_RUN=1; ZIP=1; PUBLISH=1 ;;
  *) echo "usage: scripts/release.sh [--zip | --publish | --share]" >&2; exit 2 ;;
esac
REPO=saroj-shahi/vibecheck
TAP=saroj-shahi/homebrew-tap
PROFILE="${VIBECHECK_NOTARY_PROFILE:-vibecheck-notary}"
APP=build/VibeCheck.app
OUT=build/release
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Resources/Info.plist)
DMG="$OUT/VibeCheck-$VERSION.dmg"

step() { printf '\n==> %s\n' "$*"; }
die() { echo "error: $*" >&2; exit 1; }
TAG="v$VERSION"

# --publish: fail before the long build, not after it.
if [ "$PUBLISH" = 1 ]; then
  command -v gh >/dev/null || die "--publish needs the GitHub CLI (brew install gh)"
  gh auth status >/dev/null 2>&1 || die "gh isn't signed in; run: gh auth login"
  [ -z "$(git status --porcelain --untracked-files=no)" ] || die "commit or stash your changes first; the tag must match what was built"
  [ "$(git rev-parse --abbrev-ref HEAD)" = main ] || die "releases are tagged on main (you're on $(git rev-parse --abbrev-ref HEAD))"
  git fetch -q origin main
  [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || die "push main first; HEAD isn't origin/main"
  if [ -n "${VIBECHECK_RELEASE_NOTES:-}" ]; then
    [ -f "$VIBECHECK_RELEASE_NOTES" ] || die "VIBECHECK_RELEASE_NOTES points at a missing file: $VIBECHECK_RELEASE_NOTES"
  fi
fi

# Temp folders for --publish, removed however the script ends.
WORK=""
cleanup() { [ -z "$WORK" ] || rm -rf "$WORK"; }

confirm() {
  printf '\n%s [y/N] ' "$1"
  local answer=""
  read -r answer || true
  [ "$answer" = y ] || [ "$answer" = Y ] || die "stopped; nothing more was published"
}

# Writes packaging/homebrew/vibecheck.rb into the tap as Casks/vibecheck.rb with this version and sha256, and
# pushes. The repo copy is the source; edit the cask there, never in the tap.
update_tap() {
  local sha="$1" tap="$WORK/tap"
  step "Updating the Homebrew cask in $TAP"
  gh repo clone "$TAP" "$tap" -- -q
  sed -e "s|^  version \".*\"|  version \"$VERSION\"|" \
      -e "s|^  sha256 \".*|  sha256 \"$sha\"|" \
      packaging/homebrew/vibecheck.rb > "$tap/Casks/vibecheck.rb"
  grep -q "^  version \"$VERSION\"$" "$tap/Casks/vibecheck.rb" || die "couldn't set version in the cask"
  grep -q "^  sha256 \"$sha\"$" "$tap/Casks/vibecheck.rb" || die "couldn't set sha256 in the cask"
  git -C "$tap" add Casks/vibecheck.rb
  if git -C "$tap" diff --cached --quiet; then
    echo "The tap already has VibeCheck $VERSION ($sha)."
  else
    git -C "$tap" commit -q -m "vibecheck $VERSION"
    git -C "$tap" push -q
  fi
  step "Published VibeCheck $VERSION"
  echo "Release: https://github.com/$REPO/releases/tag/$TAG"
  echo "Check it: brew update && brew upgrade --cask saroj-shahi/tap/vibecheck"
}

RELEASE=none
if [ "$PUBLISH" = 1 ]; then
  if view=$(gh release view "$TAG" -R "$REPO" --json isDraft --jq .isDraft 2>&1); then
    if [ "$view" = true ]; then RELEASE=draft; else RELEASE=public; fi
  elif [[ "$view" != *"not found"* ]]; then
    die "couldn't check GitHub for release $TAG: $view"
  fi
  if [ "$RELEASE" = public ]; then
    # Resume a run that published the release but didn't reach the tap. Use the released zip's checksum; a
    # rebuild would produce a different zip.
    echo "Release $TAG is already public; only the Homebrew cask will be updated."
    WORK=$(mktemp -d); trap cleanup EXIT
    gh release download "$TAG" -R "$REPO" -p VibeCheck.zip.sha256 -D "$WORK"
    SHA=$(cut -d' ' -f1 "$WORK/VibeCheck.zip.sha256")
    [[ "$SHA" =~ ^[0-9a-f]{64}$ ]] || die "VibeCheck.zip.sha256 on release $TAG doesn't hold a checksum"
    confirm "Point $TAP at VibeCheck $VERSION ($SHA)?"
    update_tap "$SHA"
    exit 0
  fi
fi

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
  if [ "$ZIP" = 1 ]; then
    echo "Zip build: Apple Development identity, not notarized. Installs from Terminal (curl or Homebrew), which"
    echo "doesn't quarantine the download."
  else
    echo "Share build: no Developer ID, not notarized. On other Macs, macOS blocks it until the person clears the quarantine"
    echo "flag with one Terminal command (the DMG includes a note saying how)."
  fi
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

step "Building VibeCheck $VERSION ($BUILD_NUMBER), universal"
# Releases run on Apple silicon and Intel Macs.
export VIBECHECK_ARCHS="arm64 x86_64"
./build.sh
rm -rf "$OUT" && mkdir -p "$OUT"

step "Checking the signature"
codesign --verify --deep --strict --verbose=2 "$APP"
[[ "$(codesign -dv "$APP" 2>&1)" == *"(runtime)"* ]] || die "hardened runtime is off"
[ -d "$APP/Contents/PlugIns/VibeCheckWidget.appex" ] || echo "warning: no widget extension in this build" >&2
for binary in "$APP/Contents/MacOS/VibeCheck" "$APP/Contents/PlugIns/VibeCheckWidget.appex/Contents/MacOS/VibeCheckWidget"; do
  [ -f "$binary" ] || continue
  for arch in arm64 x86_64; do
    lipo "$binary" -verify_arch "$arch" || die "$(basename "$binary") is missing $arch (lipo -archs: $(lipo -archs "$binary"))"
  done
done

# Publishes build/release/VibeCheck.zip as GitHub release $TAG and points the tap's cask at it.
publish() {
  confirm "Publish VibeCheck $VERSION: push tag $TAG, create the GitHub release and update $TAP?"
  WORK=$(mktemp -d); trap cleanup EXIT

  step "Tagging $TAG"
  git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || git tag "$TAG"
  [ "$(git rev-parse "$TAG^{commit}")" = "$(git rev-parse HEAD)" ] || die "tag $TAG exists and points elsewhere"
  git push origin "refs/tags/$TAG"

  if [ "$RELEASE" = draft ]; then
    step "Removing the draft left by an earlier run"
    gh release delete "$TAG" -R "$REPO" --yes
  fi

  step "Creating the GitHub release (draft until checked)"
  local notes=(--generate-notes)
  [ -n "${VIBECHECK_RELEASE_NOTES:-}" ] && notes=(--notes-file "$VIBECHECK_RELEASE_NOTES")
  gh release create "$TAG" -R "$REPO" --draft --verify-tag --title "VibeCheck $VERSION" "${notes[@]}" \
    "$ZIPFILE" "$ZIPFILE.sha256"

  step "Checking the uploaded zip"
  gh release download "$TAG" -R "$REPO" -p VibeCheck.zip -D "$WORK"
  [ "$(shasum -a 256 "$WORK/VibeCheck.zip" | cut -d' ' -f1)" = "$SHA" ] || die "the uploaded zip doesn't match $SHA (the release is still a draft)"

  step "Making the release public"
  gh release edit "$TAG" -R "$REPO" --draft=false --latest

  update_tap "$SHA"
  exit 0
}

if [ "$ZIP" = 1 ]; then
  step "Making the zip"
  ZIPFILE="$OUT/VibeCheck.zip"
  ditto -c -k --keepParent "$APP" "$ZIPFILE"
  (cd "$OUT" && shasum -a 256 VibeCheck.zip > VibeCheck.zip.sha256)
  SHA=$(cut -d' ' -f1 "$ZIPFILE.sha256")
  # The zip must unpack to an app whose signature still holds.
  CHECK=$(mktemp -d)
  ditto -x -k "$ZIPFILE" "$CHECK"
  codesign --verify --deep --strict "$CHECK/VibeCheck.app" || die "the app inside the zip fails codesign --verify"
  rm -rf "$CHECK"
  step "Done: $ZIPFILE"
  cat "$ZIPFILE.sha256"
  [ "$PUBLISH" = 1 ] && publish
  cat <<EOF

Homebrew cask (saroj-shahi/homebrew-tap, Casks/vibecheck.rb):
  version "$VERSION"
  sha256 "$SHA"

To publish (scripts/install.sh, the cask and the app's update check read the GitHub release; the tag must be
v$VERSION and the release must carry VibeCheck.zip and VibeCheck.zip.sha256):
  git tag v$VERSION && git push origin v$VERSION
  gh release create v$VERSION $ZIPFILE $ZIPFILE.sha256 --title "VibeCheck $VERSION" --notes "…"
EOF
  exit 0
fi

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
