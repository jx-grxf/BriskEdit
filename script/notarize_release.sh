#!/usr/bin/env bash
# Submit dist/BriskEdit-<version>.dmg for Apple notarization and staple the ticket.
#
# This is a no-op when BRISKEDIT_NOTARY_ENABLED != "true" so PRs from forks
# without the secret do not fail the release pipeline.
#
# Auth methods, in order of precedence:
#   1. BRISKEDIT_NOTARY_KEYCHAIN_PROFILE   local: profile from `notarytool store-credentials`
#   2. App Store Connect API key            preferred on CI (independent of the
#      Apple ID's password/2FA):
#        BRISKEDIT_NOTARY_KEY_ID            key ID, e.g. ABC123DEF4
#        BRISKEDIT_NOTARY_ISSUER_ID         issuer UUID
#        BRISKEDIT_NOTARY_KEY_PATH          path to the .p8 (local), or
#        BRISKEDIT_NOTARY_KEY_P8_BASE64     base64 .p8 content (CI secret)
#   3. Apple ID + app-specific password:
#        BRISKEDIT_NOTARY_APPLE_ID / BRISKEDIT_NOTARY_TEAM_ID / BRISKEDIT_NOTARY_PASSWORD
#
# Other inputs (env):
#   BRISKEDIT_VERSION                    required
#   BRISKEDIT_UPDATE_CHANNEL             stable or beta
set -euo pipefail

cd "$(dirname "$0")/.."

: "${BRISKEDIT_VERSION:?BRISKEDIT_VERSION is required}"
CHANNEL="${BRISKEDIT_UPDATE_CHANNEL:-stable}"

if [[ "${BRISKEDIT_NOTARY_ENABLED:-}" != "true" ]]; then
  echo "Notarization skipped (BRISKEDIT_NOTARY_ENABLED != true; ad-hoc developer preview)"
  exit 0
fi

DMG="dist/BriskEdit-${BRISKEDIT_VERSION}.dmg"
[[ -f "$DMG" ]] || { echo "error: $DMG not found" >&2; exit 1; }

if [[ -n "${BRISKEDIT_NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
  xcrun notarytool submit "$DMG" \
    --keychain-profile "$BRISKEDIT_NOTARY_KEYCHAIN_PROFILE" \
    --wait
elif [[ -n "${BRISKEDIT_NOTARY_KEY_PATH:-}" || -n "${BRISKEDIT_NOTARY_KEY_P8_BASE64:-}" ]]; then
  : "${BRISKEDIT_NOTARY_KEY_ID:?required with API-key auth}"
  : "${BRISKEDIT_NOTARY_ISSUER_ID:?required with API-key auth}"
  KEY_PATH="${BRISKEDIT_NOTARY_KEY_PATH:-}"
  if [[ -z "$KEY_PATH" ]]; then
    KEY_DIR="$(mktemp -d)"
    KEY_PATH="$KEY_DIR/AuthKey_${BRISKEDIT_NOTARY_KEY_ID}.p8"
    printf '%s' "$BRISKEDIT_NOTARY_KEY_P8_BASE64" | base64 --decode > "$KEY_PATH"
    trap 'rm -rf "$KEY_DIR"' EXIT
  fi
  xcrun notarytool submit "$DMG" \
    --key "$KEY_PATH" \
    --key-id "$BRISKEDIT_NOTARY_KEY_ID" \
    --issuer "$BRISKEDIT_NOTARY_ISSUER_ID" \
    --wait
else
  : "${BRISKEDIT_NOTARY_APPLE_ID:?required}"
  : "${BRISKEDIT_NOTARY_TEAM_ID:?required}"
  : "${BRISKEDIT_NOTARY_PASSWORD:?required}"
  xcrun notarytool submit "$DMG" \
    --apple-id "$BRISKEDIT_NOTARY_APPLE_ID" \
    --team-id "$BRISKEDIT_NOTARY_TEAM_ID" \
    --password "$BRISKEDIT_NOTARY_PASSWORD" \
    --wait
fi

xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

if [[ "$CHANNEL" == "stable" ]]; then
  codesign --verify --deep --strict dist/BriskEdit.app
  spctl --assess --type execute -v dist/BriskEdit.app
  spctl --assess --type open --context context:primary-signature -v "$DMG"
fi
