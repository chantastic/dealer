#!/usr/bin/env bash
# Builds build/Dealer.app from the SwiftPM "Dealer" executable.
#
# Environment:
#   CONFIG=release|debug     build configuration (default: release)
#   UNIVERSAL=1              build arm64 + x86_64 (needs full Xcode, not just CLT)
#   SIGN_IDENTITY="..."      codesign identity; default "-" (ad-hoc). Use your
#                            "Developer ID Application: …" identity for distribution.
#   VERSION=1.2.3            sets CFBundleShortVersionString (a leading "v" and any
#                            "-prerelease" suffix are dropped; must be 1-3 numbers)
#   BUILD_NUMBER=42          sets CFBundleVersion (digits and dots only)
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "build-app.sh: Dealer.app can only be built on macOS" >&2
  exit 1
fi

CONFIG="${CONFIG:-release}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
APP="build/Dealer.app"
PLIST="$APP/Contents/Info.plist"

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
# Shipping the CLI inside the bundle lets installers (e.g. a Homebrew cask) link it onto PATH.
cp "$BIN_DIR/deal" "$APP/Contents/MacOS/deal"
cp "$BIN_DIR/deal" build/deal
cp Resources/Info.plist "$PLIST"
cp Resources/MenuBarIconTemplate.png Resources/MenuBarIconTemplate@2x.png "$APP/Contents/Resources/"
iconutil --convert icns Resources/AppIcon.iconset --output "$APP/Contents/Resources/AppIcon.icns"

if [[ -n "${VERSION:-}" ]]; then
  short="${VERSION#v}"
  short="${short%%-*}"
  if [[ ! "$short" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
    echo "build-app.sh: VERSION=$VERSION doesn't start with 1-3 dot-separated numbers" >&2
    exit 1
  fi
  plutil -replace CFBundleShortVersionString -string "$short" "$PLIST"
fi
if [[ -n "${BUILD_NUMBER:-}" ]]; then
  if [[ ! "$BUILD_NUMBER" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
    echo "build-app.sh: BUILD_NUMBER=$BUILD_NUMBER must be digits and dots" >&2
    exit 1
  fi
  plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$PLIST"
fi

codesign_flags=(--force --sign "$SIGN_IDENTITY")
if [[ "$SIGN_IDENTITY" != "-" ]]; then
  codesign_flags+=(--options runtime --timestamp)
fi
# Sign nested code before the bundle that seals it.
codesign "${codesign_flags[@]}" "$APP/Contents/MacOS/deal"
codesign "${codesign_flags[@]}" --entitlements Resources/Dealer.entitlements "$APP"

echo "Built $APP $(plutil -extract CFBundleShortVersionString raw "$PLIST") ($(plutil -extract CFBundleVersion raw "$PLIST")), signed with: $SIGN_IDENTITY"
