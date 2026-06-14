#!/usr/bin/env bash
# Extract one version section from RELEASE_NOTES.md for a GitHub release body.
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${1:?usage: extract_release_notes.sh VERSION OUTPUT}"
OUTPUT="${2:?usage: extract_release_notes.sh VERSION OUTPUT}"

awk -v version="$VERSION" '
  $1 == "##" && $2 == version { found = 1 }
  found && $1 == "##" && $2 != version { exit }
  found { print }
  END { if (!found) exit 1 }
' RELEASE_NOTES.md > "$OUTPUT"

[[ -s "$OUTPUT" ]] || { echo "error: release notes for $VERSION are empty" >&2; exit 1; }
