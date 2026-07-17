#!/usr/bin/env bash
# Fail before an expensive release build when required signing inputs are absent.
# Secret values are never printed.
set -euo pipefail

cd "$(dirname "$0")/.."

require_secret() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "error: required release secret $name is not configured" >&2
    return 1
  fi
}

fail=0
require_secret BRISKEDIT_SPARKLE_PRIVATE_KEY || fail=1
require_secret BRISKEDIT_SPARKLE_PUBLIC_KEY || fail=1

canonical_public_key="$(awk -F'"' '/BRISKEDIT_SPARKLE_PUBLIC_KEY:/ { print $2; exit }' project.yml)"
if [[ -n "${BRISKEDIT_SPARKLE_PUBLIC_KEY:-}" && "$BRISKEDIT_SPARKLE_PUBLIC_KEY" != "$canonical_public_key" ]]; then
  echo "error: BRISKEDIT_SPARKLE_PUBLIC_KEY does not match project.yml" >&2
  fail=1
fi

if [[ -n "${BRISKEDIT_SIGN_IDENTITY:-}" ]]; then
  require_secret BRISKEDIT_SIGN_P12_BASE64 || fail=1
  require_secret BRISKEDIT_SIGN_P12_PASSWORD || fail=1
fi

if [[ "${BRISKEDIT_NOTARY_ENABLED:-}" == "true" ]]; then
  require_secret BRISKEDIT_SIGN_IDENTITY || fail=1
  if [[ -z "${BRISKEDIT_NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
    if [[ -n "${BRISKEDIT_NOTARY_KEY_P8_BASE64:-}" || -n "${BRISKEDIT_NOTARY_KEY_PATH:-}" ]]; then
      require_secret BRISKEDIT_NOTARY_KEY_ID || fail=1
      require_secret BRISKEDIT_NOTARY_ISSUER_ID || fail=1
    else
      require_secret BRISKEDIT_NOTARY_APPLE_ID || fail=1
      require_secret BRISKEDIT_NOTARY_TEAM_ID || fail=1
      require_secret BRISKEDIT_NOTARY_PASSWORD || fail=1
    fi
  fi
fi

if [[ "$fail" -ne 0 ]]; then
  exit 1
fi

echo "release secrets ok"
