#!/usr/bin/env bash
# Prints Casks/dealer.rb with `version` and `sha256` set for a release.
#
# Usage: scripts/update-cask.sh <version> <path-to-Dealer.dmg> > dealer.rb
#   e.g. scripts/update-cask.sh 1.2.0 build/Dealer.dmg
#
# Copy the output to Casks/dealer.rb in github.com/chantastic/homebrew-tap.
set -euo pipefail

cd "$(dirname "$0")/.."

version="${1:?usage: update-cask.sh <version> <path-to-Dealer.dmg>}"
dmg="${2:?usage: update-cask.sh <version> <path-to-Dealer.dmg>}"
version="${version#v}"

[[ "$version" =~ ^[0-9]+(\.[0-9]+){0,2}(-[0-9A-Za-z.-]+)?$ ]] || { echo "update-cask.sh: bad version $version" >&2; exit 1; }
[[ -f "$dmg" ]] || { echo "update-cask.sh: $dmg not found" >&2; exit 1; }

if command -v shasum >/dev/null; then
  sha="$(shasum -a 256 "$dmg" | awk '{print $1}')"
else
  sha="$(sha256sum "$dmg" | awk '{print $1}')"
fi

# Drop the template's header comment and set version/sha256.
sed -e '/^#/d' \
    -e "s/^  version \".*\"$/  version \"$version\"/" \
    -e "s/^  sha256 \".*\"$/  sha256 \"$sha\"/" \
    Casks/dealer.rb
