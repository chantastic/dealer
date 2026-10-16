#!/usr/bin/env bash
# Submits a file to Apple's notary service and staples the ticket.
#
# Usage: scripts/notarize.sh <file-to-submit> <path-to-staple>
#   e.g. scripts/notarize.sh build/notarize.zip build/Dealer.app
#        scripts/notarize.sh build/Dealer.dmg build/Dealer.dmg
#
# Credentials, either of (App Store Connect API key preferred):
#   APPLE_API_KEY_P8_BASE64, APPLE_API_KEY_ID, APPLE_API_ISSUER_ID
#   APPLE_ID, APPLE_TEAM_ID, APPLE_APP_SPECIFIC_PASSWORD
#
# Skips (exit 0) when no credentials are set or SIGN_IDENTITY is ad-hoc, because Apple
# only notarizes Developer ID-signed code.
set -euo pipefail

submit="${1:?usage: notarize.sh <file-to-submit> <path-to-staple>}"
staple="${2:?usage: notarize.sh <file-to-submit> <path-to-staple>}"

if [[ "${SIGN_IDENTITY:--}" == "-" ]]; then
  echo "notarize.sh: ad-hoc signed build; skipping notarization of $submit"
  exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

if [[ -n "${APPLE_API_KEY_P8_BASE64:-}" && -n "${APPLE_API_KEY_ID:-}" && -n "${APPLE_API_ISSUER_ID:-}" ]]; then
  echo "$APPLE_API_KEY_P8_BASE64" | base64 --decode > "$work/AuthKey.p8"
  auth=(--key "$work/AuthKey.p8" --key-id "$APPLE_API_KEY_ID" --issuer "$APPLE_API_ISSUER_ID")
elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]]; then
  auth=(--apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD")
else
  echo "notarize.sh: no notarization credentials; skipping notarization of $submit"
  exit 0
fi

echo "notarize.sh: submitting $submit"
xcrun notarytool submit "$submit" "${auth[@]}" --wait --timeout 30m --output-format json > "$work/result.json" || true
cat "$work/result.json"
status="$(plutil -extract status raw -o - "$work/result.json" 2>/dev/null || echo unknown)"
if [[ "$status" != "Accepted" ]]; then
  id="$(plutil -extract id raw -o - "$work/result.json" 2>/dev/null || true)"
  [[ -n "$id" ]] && xcrun notarytool log "$id" "${auth[@]}" || true
  echo "notarize.sh: notarization of $submit finished with status: $status" >&2
  exit 1
fi

xcrun stapler staple "$staple"
xcrun stapler validate "$staple"
