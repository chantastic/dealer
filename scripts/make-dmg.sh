#!/usr/bin/env bash
# Packages build/Dealer.app into build/Dealer.dmg: a compressed, read-only disk image whose
# window shows Dealer.app next to an Applications shortcut, so installing is a drag.
#
# Environment:
#   SIGN_IDENTITY="..."   signs the disk image too when it's a real identity (not "-")
set -euo pipefail

cd "$(dirname "$0")/.."

APP="build/Dealer.app"
DMG="build/Dealer.dmg"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

[[ -d "$APP" ]] || { echo "make-dmg.sh: $APP not found; run scripts/build-app.sh first" >&2; exit 1; }

staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT

ditto "$APP" "$staging/Dealer.app"
ln -s /Applications "$staging/Applications"

# Give the mounted volume Dealer's icon (SetFile ships with the Xcode command line tools).
if command -v SetFile >/dev/null; then
  cp "$APP/Contents/Resources/AppIcon.icns" "$staging/.VolumeIcon.icns"
  SetFile -a C "$staging"
fi

rm -f "$DMG"
hdiutil create -volname "Dealer" -srcfolder "$staging" -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$DMG"

if [[ "$SIGN_IDENTITY" != "-" ]]; then
  codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG"
fi

echo "Built $DMG"
