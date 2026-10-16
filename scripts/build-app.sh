#!/usr/bin/env bash
# Builds build/Dealer.app from the SwiftPM "Dealer" executable.
#
# Environment:
#   CONFIG=release|debug     build configuration (default: release)
#   UNIVERSAL=1              build arm64 + x86_64 (needs full Xcode, not just CLT)
#   SIGN_IDENTITY="..."      codesign identity; default "-" (ad-hoc). Use your
#                            "Developer ID Application: …" identity for distribution.
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "build-app.sh: Dealer.app can only be built on macOS" >&2
  exit 1
fi

CONFIG="${CONFIG:-release}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
APP="build/Dealer.app"

build_flags=(-c "$CONFIG")
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  build_flags+=(--arch arm64 --arch x86_64)
fi

swift build "${build_flags[@]}" --product Dealer
swift build "${build_flags[@]}" --product deal
BIN_DIR="$(swift build "${build_flags[@]}" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Dealer" "$APP/Contents/MacOS/Dealer"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "$BIN_DIR/deal" build/deal

codesign_flags=(--force --sign "$SIGN_IDENTITY")
if [[ "$SIGN_IDENTITY" != "-" ]]; then
  codesign_flags+=(--options runtime --timestamp)
fi
codesign "${codesign_flags[@]}" "$APP"

echo "Built $APP (signed with: $SIGN_IDENTITY)"
