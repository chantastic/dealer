#!/usr/bin/env bash
# Builds the release artifacts: build/Dealer.zip, build/Dealer.dmg, and build/SHA256SUMS.txt.
# The release workflow and the CI dry run both use this, so they produce the same layout.
#
# Order matters for notarization: notarize and staple the app first, then zip it and put the
# stapled app in the disk image, then notarize and staple the image.
#
# Environment: VERSION, BUILD_NUMBER, SIGN_IDENTITY (see build-app.sh) and the notarization
# credentials (see notarize.sh). Builds universal binaries unless UNIVERSAL=0.
set -euo pipefail

cd "$(dirname "$0")/.."

export UNIVERSAL="${UNIVERSAL:-1}"
export SIGN_IDENTITY="${SIGN_IDENTITY:--}"

scripts/build-app.sh

zip_app() { ditto -c -k --sequesterRsrc --keepParent build/Dealer.app "$1"; }

zip_app build/notarize.zip
scripts/notarize.sh build/notarize.zip build/Dealer.app
rm -f build/notarize.zip

rm -f build/Dealer.zip
zip_app build/Dealer.zip

scripts/make-dmg.sh
scripts/notarize.sh build/Dealer.dmg build/Dealer.dmg

(cd build && shasum -a 256 Dealer.dmg Dealer.zip > SHA256SUMS.txt)
cat build/SHA256SUMS.txt
