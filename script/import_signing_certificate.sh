#!/usr/bin/env bash
# Import the Developer ID Application certificate into a dedicated temporary
# keychain so xcodebuild can sign on an ephemeral CI runner.
#
# This is a no-op when BRISKEDIT_SIGN_P12_BASE64 is unset so unsigned
# developer-preview releases keep working without the secret.
#
# Inputs (env):
#   BRISKEDIT_SIGN_P12_BASE64    base64-encoded .p12 export of the certificate
#   BRISKEDIT_SIGN_P12_PASSWORD  password protecting the .p12
set -euo pipefail

if [[ -z "${BRISKEDIT_SIGN_P12_BASE64:-}" ]]; then
  echo "Signing certificate import skipped (BRISKEDIT_SIGN_P12_BASE64 not set)"
  exit 0
fi
: "${BRISKEDIT_SIGN_P12_PASSWORD:?BRISKEDIT_SIGN_P12_PASSWORD is required}"

TMP_DIR="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
KEYCHAIN_PATH="$TMP_DIR/briskedit-signing.keychain-db"
KEYCHAIN_PASSWORD="$(uuidgen)"
CERT_PATH="$TMP_DIR/briskedit-signing.p12"

cleanup_cert() { rm -f "$CERT_PATH"; }
trap cleanup_cert EXIT

printf '%s' "$BRISKEDIT_SIGN_P12_BASE64" | base64 --decode > "$CERT_PATH"

security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
# Auto-lock after 6h so a hung job cannot leave it open indefinitely.
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security import "$CERT_PATH" \
  -k "$KEYCHAIN_PATH" \
  -P "$BRISKEDIT_SIGN_P12_PASSWORD" \
  -T /usr/bin/codesign \
  -T /usr/bin/security
# Allow codesign to use the key without a UI prompt (headless runner).
security set-key-partition-list -S apple-tool:,apple: \
  -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH" >/dev/null
security list-keychains -d user -s "$KEYCHAIN_PATH" login.keychain-db

security find-identity -v -p codesigning "$KEYCHAIN_PATH" | grep -q "Developer ID Application" || {
  echo "error: imported keychain contains no Developer ID Application identity" >&2
  exit 1
}
echo "Signing keychain ready"
