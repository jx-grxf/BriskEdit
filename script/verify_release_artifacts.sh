#!/usr/bin/env bash
# Validate every distributable before publishing and write SHA256SUMS.
set -euo pipefail

cd "$(dirname "$0")/.."

: "${BRISKEDIT_VERSION:?BRISKEDIT_VERSION is required}"
: "${BRISKEDIT_BUILD:?BRISKEDIT_BUILD is required}"
: "${BRISKEDIT_UPDATE_CHANNEL:?BRISKEDIT_UPDATE_CHANNEL is required}"
: "${BRISKEDIT_RELEASE_TAG:?BRISKEDIT_RELEASE_TAG is required}"

APP="dist/BriskEdit.app"
DMG="dist/BriskEdit-${BRISKEDIT_VERSION}.dmg"
ZIP="dist/sparkle/BriskEdit-${BRISKEDIT_VERSION}.zip"
APPCAST="dist/sparkle/appcast.xml"

for path in "$APP" "$DMG" "$ZIP" "$APPCAST"; do
  [[ -e "$path" ]] || { echo "error: release artifact missing: $path" >&2; exit 1; }
done

INFO="$APP/Contents/Info.plist"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO")" == "com.johannesgrof.briskedit" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO")" == "$BRISKEDIT_VERSION" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO")" == "$BRISKEDIT_BUILD" ]]
[[ -n "$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$INFO")" ]]

codesign --verify --deep --strict "$APP"
lipo -archs "$APP/Contents/MacOS/BriskEdit" | grep -qw arm64
hdiutil imageinfo "$DMG" >/dev/null
unzip -tq "$ZIP" >/dev/null

./script/verify_appcast.swift \
  "$APPCAST" \
  "https://github.com/${GITHUB_REPOSITORY:-jx-grxf/BriskEdit}/releases/download/${BRISKEDIT_RELEASE_TAG}/BriskEdit-${BRISKEDIT_VERSION}.zip" \
  "$BRISKEDIT_UPDATE_CHANNEL" \
  "$BRISKEDIT_VERSION" \
  "$BRISKEDIT_BUILD" \
  "$ZIP"

if [[ "${BRISKEDIT_NOTARY_ENABLED:-}" == "true" ]]; then
  xcrun stapler validate "$DMG"
fi

(
  cd dist
  shasum -a 256 "BriskEdit-${BRISKEDIT_VERSION}.dmg"
  shasum -a 256 "sparkle/BriskEdit-${BRISKEDIT_VERSION}.zip" \
    | sed 's#  sparkle/#  #'
  shasum -a 256 "sparkle/appcast.xml" \
    | sed 's#  sparkle/#  #'
) > dist/SHA256SUMS

echo "release artifacts ok"
