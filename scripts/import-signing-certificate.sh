#!/usr/bin/env bash
# CI helper: imports a Developer ID certificate into a temporary keychain and exports
# SIGN_IDENTITY to later steps via $GITHUB_ENV. Without a certificate it exports
# SIGN_IDENTITY=- so the build is ad-hoc signed instead.
#
# Environment:
#   MACOS_CERTIFICATE_P12_BASE64   base64 of a .p12 containing "Developer ID Application: …"
#   MACOS_CERTIFICATE_PASSWORD     the .p12 password
#   MACOS_SIGNING_IDENTITY         optional; defaults to the first Developer ID Application identity
#   RUNNER_TEMP, GITHUB_ENV        provided by GitHub Actions
set -euo pipefail

env_file="${GITHUB_ENV:-/dev/stdout}"

if [[ -z "${MACOS_CERTIFICATE_P12_BASE64:-}" ]]; then
  echo "::notice::No Developer ID certificate configured; building ad-hoc signed (unnotarized) artifacts."
  echo "SIGN_IDENTITY=-" >> "$env_file"
  exit 0
fi

keychain="${RUNNER_TEMP:?}/dealer-signing.keychain-db"
keychain_password="$(uuidgen)"
certificate="${RUNNER_TEMP}/dealer-signing.p12"

echo "$MACOS_CERTIFICATE_P12_BASE64" | base64 --decode > "$certificate"
security create-keychain -p "$keychain_password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
security import "$certificate" -k "$keychain" -P "${MACOS_CERTIFICATE_PASSWORD:-}" -T /usr/bin/codesign -T /usr/bin/security
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain" >/dev/null
security list-keychains -d user -s "$keychain" $(security list-keychains -d user | tr -d '"')
rm -f "$certificate"

identity="${MACOS_SIGNING_IDENTITY:-}"
if [[ -z "$identity" ]]; then
  identity="$(security find-identity -v -p codesigning "$keychain" | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -1)"
fi
if [[ -z "$identity" ]]; then
  echo "::error::The certificate doesn't contain a \"Developer ID Application\" identity."
  exit 1
fi

echo "Signing with: $identity"
echo "SIGN_IDENTITY=$identity" >> "$env_file"
echo "SIGNING_KEYCHAIN=$keychain" >> "$env_file"
