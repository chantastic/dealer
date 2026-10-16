#!/usr/bin/env bash
# Writes build/appcast.xml for Sparkle: one item for this release, pointing at the release's
# Dealer.zip and carrying its EdDSA signature. The release workflow uploads it as a release
# asset, so SUFeedURL (…/releases/latest/download/appcast.xml) always serves the newest release.
#
# Environment:
#   SPARKLE_PRIVATE_KEY   base64 EdDSA private key (from `generate_keys -x`). If unset, this
#                         script prints a notice and exits 0 without writing an appcast.
#   VERSION               release version from the tag, e.g. 1.2.0 (no leading "v")
#   BUILD_NUMBER          CFBundleVersion of the build; Sparkle compares this to decide
#                         whether an update is newer
#   REPOSITORY            owner/repo for download URLs (default: chantastic/dealer)
#   SPARKLE_BIN           directory containing Sparkle's sign_update; downloaded if unset
#
# Usage: scripts/make-appcast.sh [archive]   (default: build/Dealer.zip)
set -euo pipefail

cd "$(dirname "$0")/.."

SPARKLE_VERSION=2.10.0 # keep in sync with Package.swift
archive="${1:-build/Dealer.zip}"
out=build/appcast.xml
repository="${REPOSITORY:-chantastic/dealer}"

if [[ -z "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  echo "::notice::SPARKLE_PRIVATE_KEY isn't set; skipping the Sparkle appcast (auto-updates won't see this release)."
  exit 0
fi
: "${VERSION:?VERSION is required}" "${BUILD_NUMBER:?BUILD_NUMBER is required}"
[[ -f "$archive" ]] || { echo "make-appcast.sh: $archive not found" >&2; exit 1; }

if [[ -z "${SPARKLE_BIN:-}" ]]; then
  tools="$(mktemp -d)"
  curl -fsSL "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz" \
    | tar -xJf - -C "$tools"
  SPARKLE_BIN="$(dirname "$(find "$tools" -name sign_update -type f | head -1)")"
fi

# sign_update prints: sparkle:edSignature="…" length="…"
attributes="$(printf '%s\n' "$SPARKLE_PRIVATE_KEY" | "$SPARKLE_BIN/sign_update" --ed-key-file - "$archive")"
[[ "$attributes" =~ sparkle:edSignature=\"[^\"]+\"\ length=\"[0-9]+\" ]] || {
  echo "make-appcast.sh: unexpected sign_update output: $attributes" >&2
  exit 1
}

short="${VERSION%%-*}"
minimum_os="$(plutil -extract LSMinimumSystemVersion raw Resources/Info.plist 2>/dev/null || echo 13.0)"
published="$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")"
tag="v$VERSION"

cat > "$out" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Dealer</title>
    <link>https://github.com/$repository</link>
    <description>Dealer release feed</description>
    <language>en</language>
    <item>
      <title>Dealer $VERSION</title>
      <pubDate>$published</pubDate>
      <sparkle:version>$BUILD_NUMBER</sparkle:version>
      <sparkle:shortVersionString>$short</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$minimum_os</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>https://github.com/$repository/releases/tag/$tag</sparkle:releaseNotesLink>
      <enclosure url="https://github.com/$repository/releases/download/$tag/$(basename "$archive")" type="application/octet-stream" $attributes/>
    </item>
  </channel>
</rss>
XML

echo "Wrote $out"
cat "$out"
