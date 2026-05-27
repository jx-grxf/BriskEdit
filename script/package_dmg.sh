#!/usr/bin/env bash
# Build a Release BriskEdit.app and package it into a DMG.
#
# Inputs (env):
#   BRISKEDIT_VERSION              required, e.g. 0.1.0
#   BRISKEDIT_BUILD                optional, defaults to 1
#   BRISKEDIT_SPARKLE_PUBLIC_KEY   optional, embeds into Info.plist when present
#   BRISKEDIT_SIGN_IDENTITY        optional, Developer ID Application identity
#
# Output:
#   dist/BriskEdit.app
#   dist/BriskEdit-<version>.dmg
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ -z "${BRISKEDIT_VERSION:-}" ]]; then
  echo "error: BRISKEDIT_VERSION is required" >&2
  exit 1
fi
BUILD="${BRISKEDIT_BUILD:-1}"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "error: xcodegen is required" >&2
  exit 1
fi

if ! command -v create-dmg >/dev/null 2>&1; then
  echo "error: create-dmg is required (brew install create-dmg)" >&2
  exit 1
fi

xcodegen >/dev/null

DERIVED_DATA="$(mktemp -d)"
trap 'rm -rf "$DERIVED_DATA"' EXIT

EXTRA_SETTINGS=(
  "MARKETING_VERSION=$BRISKEDIT_VERSION"
  "CURRENT_PROJECT_VERSION=$BUILD"
)
if [[ -n "${BRISKEDIT_SPARKLE_PUBLIC_KEY:-}" ]]; then
  EXTRA_SETTINGS+=("INFOPLIST_KEY_SUPublicEDKey=$BRISKEDIT_SPARKLE_PUBLIC_KEY")
fi
if [[ -n "${BRISKEDIT_SIGN_IDENTITY:-}" ]]; then
  EXTRA_SETTINGS+=(
    "CODE_SIGN_STYLE=Manual"
    "CODE_SIGN_IDENTITY=$BRISKEDIT_SIGN_IDENTITY"
    "CODE_SIGNING_REQUIRED=YES"
  )
fi

xcodebuild \
  -project BriskEdit.xcodeproj \
  -scheme BriskEdit \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  "${EXTRA_SETTINGS[@]}" \
  build | tail -20

APP_SRC="$DERIVED_DATA/Build/Products/Release/BriskEdit.app"
if [[ ! -d "$APP_SRC" ]]; then
  echo "error: $APP_SRC not produced" >&2
  exit 1
fi

mkdir -p dist
rm -rf dist/BriskEdit.app
cp -R "$APP_SRC" dist/BriskEdit.app

codesign --verify --deep --strict dist/BriskEdit.app

DMG="dist/BriskEdit-${BRISKEDIT_VERSION}.dmg"
rm -f "$DMG"

STAGE="$(mktemp -d)"
trap 'rm -rf "$DERIVED_DATA" "$STAGE"' EXIT
cp -R dist/BriskEdit.app "$STAGE/"

create-dmg \
  --volname "BriskEdit ${BRISKEDIT_VERSION}" \
  --window-pos 200 120 \
  --window-size 540 360 \
  --icon-size 96 \
  --icon "BriskEdit.app" 150 180 \
  --app-drop-link 390 180 \
  --no-internet-enable \
  "$DMG" \
  "$STAGE" \
  >/dev/null

hdiutil imageinfo "$DMG" >/dev/null
echo "Built $DMG"
