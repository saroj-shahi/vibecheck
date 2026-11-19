#!/bin/bash
# Installs (or updates) VibeCheck from the latest GitHub release.
#
#   curl -fsSL https://raw.githubusercontent.com/saroj-shahi/vibecheck/main/scripts/install.sh | bash
#   ... | bash -s -- --uninstall      removes the app, keeps your settings
#
# Installs to /Applications, or ~/Applications when /Applications isn't writable. Never uses sudo.
# For testing: VIBECHECK_ZIP_URL (any curl URL, file:// works) replaces the download, and VIBECHECK_INSTALL_DIR
# installs there instead and leaves a running VibeCheck alone (no quit, no open).
set -euo pipefail

ZIP_URL="${VIBECHECK_ZIP_URL:-https://github.com/saroj-shahi/vibecheck/releases/latest/download/VibeCheck.zip}"

say() { printf '%s\n' "$*"; }
die() { printf 'VibeCheck: %s\n' "$*" >&2; exit 1; }

TESTING=0
if [ -n "${VIBECHECK_INSTALL_DIR:-}" ]; then
  DEST="$VIBECHECK_INSTALL_DIR"; TESTING=1
elif [ -w /Applications ]; then
  DEST=/Applications
else
  DEST="$HOME/Applications"
fi
APP="$DEST/VibeCheck.app"

quit_app() { [ "$TESTING" = 1 ] || osascript -e 'quit app "VibeCheck"' >/dev/null 2>&1 || true; }

if [ "${1:-}" = "--uninstall" ]; then
  quit_app
  [ -d "$APP" ] || [ "$TESTING" = 1 ] || APP="$HOME/Applications/VibeCheck.app"
  [ -d "$APP" ] || die "no VibeCheck found in $DEST, nothing to remove."
  rm -rf "$APP"
  say "Removed $APP. Your settings are kept, in case you come back."
  exit 0
fi
[ $# -eq 0 ] || die "unknown option $1 (use --uninstall to remove the app)."

[ "$(uname -s)" = Darwin ] || die "VibeCheck is a Mac app; this isn't a Mac."
MAJOR=$(sw_vers -productVersion | cut -d. -f1)
[ "$MAJOR" -ge 14 ] || die "needs macOS 14 Sonoma or later (this Mac has $(sw_vers -productVersion))."

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

say "Downloading VibeCheck…"
curl -fsSL "$ZIP_URL" -o "$TMP/VibeCheck.zip"
curl -fsSL "$ZIP_URL.sha256" -o "$TMP/VibeCheck.zip.sha256"
(cd "$TMP" && shasum -a 256 -c VibeCheck.zip.sha256 >/dev/null) \
  || die "the download doesn't match its checksum. Nothing was installed; try again."

ditto -x -k "$TMP/VibeCheck.zip" "$TMP/unzipped"
[ -d "$TMP/unzipped/VibeCheck.app" ] || die "the download has no VibeCheck.app inside. Nothing was installed."

quit_app
mkdir -p "$DEST"
rm -rf "$APP"
ditto "$TMP/unzipped/VibeCheck.app" "$APP"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist" 2>/dev/null || echo "")
say "VibeCheck ${VERSION:+$VERSION }is installed in $DEST. Your Mac is about to get a vibe check."
[ "$TESTING" = 1 ] || open "$APP"
say "Look for the ring in your menu bar (top right). To remove it later, run this script with --uninstall."
