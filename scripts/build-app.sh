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

# Sparkle.framework (from the SwiftPM binary target) goes in Contents/Frameworks, and the
# executable needs a matching rpath to find it there.
sparkle="$(find "$BIN_DIR" .build/artifacts -maxdepth 6 -name Sparkle.framework -type d -not -path "*/Versions/*" 2>/dev/null | head -1)"
[[ -n "$sparkle" ]] || { echo "build-app.sh: Sparkle.framework not found under $BIN_DIR or .build/artifacts" >&2; exit 1; }
mkdir -p "$APP/Contents/Frameworks"
ditto "$sparkle" "$APP/Contents/Frameworks/Sparkle.framework"
if ! otool -l "$APP/Contents/MacOS/Dealer" | grep -q "@executable_path/../Frameworks"; then
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/Dealer"
fi

# Optional: inject the Sparkle public key at build time instead of committing it to Info.plist.
if [[ -n "${SPARKLE_PUBLIC_ED_KEY:-}" ]]; then
  plutil -replace SUPublicEDKey -string "$SPARKLE_PUBLIC_ED_KEY" "$PLIST"
fi

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
# Sign nested code inside-out before the bundle that seals it. Sparkle's helpers are re-signed
# with our identity, following Sparkle's documented order.
fw="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
codesign "${codesign_flags[@]}" "$fw/XPCServices/Installer.xpc"
codesign "${codesign_flags[@]}" --preserve-metadata=entitlements "$fw/XPCServices/Downloader.xpc"
codesign "${codesign_flags[@]}" "$fw/Autoupdate"
codesign "${codesign_flags[@]}" "$fw/Updater.app"
codesign "${codesign_flags[@]}" "$APP/Contents/Frameworks/Sparkle.framework"
codesign "${codesign_flags[@]}" "$APP/Contents/MacOS/deal"
codesign "${codesign_flags[@]}" --entitlements Resources/Dealer.entitlements "$APP"

updates="disabled (no SUPublicEDKey)"
[[ -n "$(plutil -extract SUPublicEDKey raw "$PLIST" 2>/dev/null)" ]] && updates="enabled"
echo "Built $APP $(plutil -extract CFBundleShortVersionString raw "$PLIST") ($(plutil -extract CFBundleVersion raw "$PLIST")), signed with: $SIGN_IDENTITY, Sparkle updates: $updates"
