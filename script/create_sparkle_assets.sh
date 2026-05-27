#!/usr/bin/env bash
# Build the Sparkle ZIP + appcast for the current BRISKEDIT_VERSION.
#
# Inputs (env):
#   BRISKEDIT_VERSION                 required
#   BRISKEDIT_BUILD                   optional, defaults to 1
#   BRISKEDIT_UPDATE_CHANNEL          optional, "stable" or "beta", defaults to stable
#   BRISKEDIT_SPARKLE_PRIVATE_KEY     required for signing
#   BRISKEDIT_SPARKLE_DOWNLOAD_PREFIX required, e.g. https://github.com/jx-grxf/BriskEdit/releases/download/v0.1.0
#
# Output:
#   dist/sparkle/BriskEdit-<version>.zip
#   dist/sparkle/appcast.xml
set -euo pipefail

cd "$(dirname "$0")/.."

: "${BRISKEDIT_VERSION:?BRISKEDIT_VERSION is required}"
: "${BRISKEDIT_SPARKLE_PRIVATE_KEY:?BRISKEDIT_SPARKLE_PRIVATE_KEY is required}"
: "${BRISKEDIT_SPARKLE_DOWNLOAD_PREFIX:?BRISKEDIT_SPARKLE_DOWNLOAD_PREFIX is required}"

CHANNEL="${BRISKEDIT_UPDATE_CHANNEL:-stable}"
BUILD="${BRISKEDIT_BUILD:-1}"

if [[ ! -d dist/BriskEdit.app ]]; then
  echo "error: dist/BriskEdit.app not found — run script/package_dmg.sh first" >&2
  exit 1
fi

mkdir -p dist/sparkle
ZIP="dist/sparkle/BriskEdit-${BRISKEDIT_VERSION}.zip"
rm -f "$ZIP"

# Sparkle expects a flat zip with BriskEdit.app at the root.
(cd dist && /usr/bin/ditto -c -k --sequesterRsrc --keepParent BriskEdit.app "sparkle/BriskEdit-${BRISKEDIT_VERSION}.zip")

# Locate Sparkle's sign_update binary from SwiftPM cache.
SIGN_UPDATE="$(find ~/Library/Developer/Xcode/DerivedData -type f -name sign_update 2>/dev/null | head -n 1 || true)"
if [[ -z "$SIGN_UPDATE" ]]; then
  SIGN_UPDATE="$(find ~/Library/Caches/org.swift.swiftpm -type f -name sign_update 2>/dev/null | head -n 1 || true)"
fi
if [[ -z "$SIGN_UPDATE" ]]; then
  echo "error: Sparkle sign_update binary not found — build the app at least once so SPM resolves Sparkle" >&2
  exit 1
fi

KEY_FILE="$(mktemp)"
trap 'rm -f "$KEY_FILE"' EXIT
printf '%s' "$BRISKEDIT_SPARKLE_PRIVATE_KEY" > "$KEY_FILE"

SIGNATURE_LINE="$("$SIGN_UPDATE" "$ZIP" -f "$KEY_FILE")"
LENGTH="$(stat -f%z "$ZIP")"
PUBDATE="$(LC_ALL=en_US date -u "+%a, %d %b %Y %H:%M:%S +0000")"
DOWNLOAD_URL="${BRISKEDIT_SPARKLE_DOWNLOAD_PREFIX%/}/BriskEdit-${BRISKEDIT_VERSION}.zip"

cat > dist/sparkle/appcast.xml <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>BriskEdit</title>
    <link>https://github.com/jx-grxf/BriskEdit</link>
    <description>BriskEdit ${CHANNEL} update feed</description>
    <language>en</language>
    <item>
      <title>BriskEdit ${BRISKEDIT_VERSION}</title>
      <sparkle:channel>${CHANNEL}</sparkle:channel>
      <sparkle:version>${BUILD}</sparkle:version>
      <sparkle:shortVersionString>${BRISKEDIT_VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
      <pubDate>${PUBDATE}</pubDate>
      <enclosure
        url="${DOWNLOAD_URL}"
        length="${LENGTH}"
        type="application/octet-stream"
        ${SIGNATURE_LINE} />
    </item>
  </channel>
</rss>
EOF

echo "Wrote $ZIP"
echo "Wrote dist/sparkle/appcast.xml"
