#!/usr/bin/env bash
# Submit dist/BriskEdit-<version>.dmg for Apple notarization and staple the ticket.
#
# This is a no-op when BRISKEDIT_NOTARY_ENABLED != "true" so PRs from forks
# without the secret do not fail the release pipeline.
#
# Inputs (env):
#   BRISKEDIT_VERSION                    required
#   BRISKEDIT_UPDATE_CHANNEL             stable or beta; stable requires notarization
#   BRISKEDIT_NOTARY_ENABLED             "true" to actually submit, anything else skips
#   BRISKEDIT_NOTARY_APPLE_ID            Apple ID email
#   BRISKEDIT_NOTARY_TEAM_ID             Developer Team ID (10-char)
#   BRISKEDIT_NOTARY_PASSWORD            App-specific password
#   BRISKEDIT_NOTARY_KEYCHAIN_PROFILE    optional, prefer this if set
set -euo pipefail

cd "$(dirname "$0")/.."

: "${BRISKEDIT_VERSION:?BRISKEDIT_VERSION is required}"
CHANNEL="${BRISKEDIT_UPDATE_CHANNEL:-stable}"

if [[ "${BRISKEDIT_NOTARY_ENABLED:-}" != "true" ]]; then
  if [[ "$CHANNEL" == "stable" ]]; then
    echo "error: stable releases require notarization (set BRISKEDIT_NOTARY_ENABLED=true)" >&2
    exit 1
  fi
  echo "Notarization skipped (BRISKEDIT_NOTARY_ENABLED != true)"
  exit 0
fi

DMG="dist/BriskEdit-${BRISKEDIT_VERSION}.dmg"
[[ -f "$DMG" ]] || { echo "error: $DMG not found" >&2; exit 1; }

if [[ -n "${BRISKEDIT_NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
  xcrun notarytool submit "$DMG" \
    --keychain-profile "$BRISKEDIT_NOTARY_KEYCHAIN_PROFILE" \
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
