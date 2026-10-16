#!/usr/bin/env bash
# Checks the artifacts from package-release.sh. Used by CI and the release workflow.
#
# Environment:
#   EXPECT_VERSION, EXPECT_BUILD   optional; compared with the app's Info.plist
set -euo pipefail

cd "$(dirname "$0")/.."

fail() { echo "verify-package.sh: $*" >&2; exit 1; }

app=build/Dealer.app
plist="$app/Contents/Info.plist"

for binary in "$app/Contents/MacOS/Dealer" "$app/Contents/MacOS/deal"; do
  archs="$(lipo -archs "$binary")"
  [[ "$archs" == *arm64* && "$archs" == *x86_64* ]] || fail "$binary is not universal: $archs"
done

[[ -f "$app/Contents/Resources/AppIcon.icns" ]] || fail "AppIcon.icns missing"
[[ -f "$app/Contents/Resources/MenuBarIconTemplate.png" ]] || fail "menu-bar icon missing"
[[ "$(plutil -extract CFBundleIconFile raw "$plist")" == "AppIcon" ]] || fail "CFBundleIconFile isn't AppIcon"

version="$(plutil -extract CFBundleShortVersionString raw "$plist")"
build="$(plutil -extract CFBundleVersion raw "$plist")"
[[ -z "${EXPECT_VERSION:-}" || "$version" == "$EXPECT_VERSION" ]] || fail "version $version, expected $EXPECT_VERSION"
[[ -z "${EXPECT_BUILD:-}" || "$build" == "$EXPECT_BUILD" ]] || fail "build $build, expected $EXPECT_BUILD"

codesign --verify --strict --deep --verbose=2 "$app"

unzip -l build/Dealer.zip | grep -q "Dealer.app/Contents/MacOS/Dealer" || fail "Dealer.zip doesn't contain Dealer.app"
(cd build && shasum -a 256 -c SHA256SUMS.txt)

mount="$(mktemp -d)"
hdiutil attach build/Dealer.dmg -readonly -nobrowse -mountpoint "$mount" >/dev/null
trap 'hdiutil detach "$mount" -quiet || true' EXIT
[[ -d "$mount/Dealer.app" ]] || fail "Dealer.dmg doesn't contain Dealer.app"
[[ "$(readlink "$mount/Applications")" == "/Applications" ]] || fail "Dealer.dmg is missing the Applications shortcut"
codesign --verify --strict --deep "$mount/Dealer.app"

echo "OK: Dealer $version ($build), universal ($(lipo -archs "$app/Contents/MacOS/Dealer")); zip, dmg, and checksums verified"
