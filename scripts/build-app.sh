#!/usr/bin/env bash
# Builds build/Earl.app from the SwiftPM "Earl" executable.
#
# Environment:
#   CONFIG=release|debug     build configuration (default: release)
#   UNIVERSAL=1              build arm64 + x86_64 (needs full Xcode, not just CLT)
#   SIGN_IDENTITY="..."      codesign identity; default "-" (ad-hoc). Use your
#                            "Developer ID Application: …" identity for distribution.
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "build-app.sh: Earl.app can only be built on macOS" >&2
  exit 1
fi

CONFIG="${CONFIG:-release}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
APP="build/Earl.app"

build_flags=(-c "$CONFIG")
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  build_flags+=(--arch arm64 --arch x86_64)
fi

swift build "${build_flags[@]}" --product Earl
swift build "${build_flags[@]}" --product earlctl
BIN_DIR="$(swift build "${build_flags[@]}" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Earl" "$APP/Contents/MacOS/Earl"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "$BIN_DIR/earlctl" build/earlctl

codesign_flags=(--force --sign "$SIGN_IDENTITY")
if [[ "$SIGN_IDENTITY" != "-" ]]; then
  codesign_flags+=(--options runtime --timestamp)
fi
codesign "${codesign_flags[@]}" "$APP"

echo "Built $APP (signed with: $SIGN_IDENTITY)"
