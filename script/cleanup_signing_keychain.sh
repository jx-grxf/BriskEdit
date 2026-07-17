#!/usr/bin/env bash
# Remove the temporary signing keychain created by import_signing_certificate.sh
# and restore the default keychain search list. Safe to run when no keychain
# was created (unsigned builds).
set -euo pipefail

TMP_DIR="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
KEYCHAIN_PATH="$TMP_DIR/briskedit-signing.keychain-db"

if [[ -f "$KEYCHAIN_PATH" ]]; then
  security delete-keychain "$KEYCHAIN_PATH"
  echo "Signing keychain removed"
fi
security list-keychains -d user -s login.keychain-db
