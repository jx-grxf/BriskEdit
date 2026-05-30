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

# Two unrelated tools share the name "create-dmg": the Homebrew formula
# create-dmg/create-dmg (bash, supports --volname for a styled layout) and the
# npm sindresorhus/create-dmg (supports --dmg-title). Prefer the styled one;
# fall back to whatever is on PATH, and ultimately to a plain hdiutil DMG.
CREATE_DMG_BIN=""
for candidate in \
  "/opt/homebrew/opt/create-dmg/bin/create-dmg" \
  "/usr/local/opt/create-dmg/bin/create-dmg" \
  "/opt/homebrew/bin/create-dmg" \
  "/usr/local/bin/create-dmg" \
  "$(command -v create-dmg 2>/dev/null || true)"; do
  [[ -z "$candidate" || ! -x "$candidate" ]] && continue
  if "$candidate" --help 2>&1 | grep -q -- "--volname"; then
    CREATE_DMG_BIN="$candidate"
    break
  fi
done
if [[ -z "$CREATE_DMG_BIN" ]]; then
  CREATE_DMG_BIN="$(command -v create-dmg 2>/dev/null || true)"
fi

xcodegen >/dev/null

# Use a stable derived-data path inside the repo (.build is gitignored) so the
# Sparkle SPM artifacts (sign_update) survive for create_sparkle_assets.sh.
DERIVED_DATA="${BRISKEDIT_DERIVED_DATA:-$PWD/.build/release-derived-data}"
rm -rf "$DERIVED_DATA"
mkdir -p "$DERIVED_DATA"

EXTRA_SETTINGS=(
  "MARKETING_VERSION=$BRISKEDIT_VERSION"
  "CURRENT_PROJECT_VERSION=$BUILD"
)
if [[ -n "${BRISKEDIT_SPARKLE_PUBLIC_KEY:-}" ]]; then
  # Build setting (not INFOPLIST_KEY_*): Config/Info.plist expands
  # $(BRISKEDIT_SPARKLE_PUBLIC_KEY) into SUPublicEDKey at build time.
  EXTRA_SETTINGS+=("BRISKEDIT_SPARKLE_PUBLIC_KEY=$BRISKEDIT_SPARKLE_PUBLIC_KEY")
fi
if [[ -n "${BRISKEDIT_SIGN_IDENTITY:-}" ]]; then
  # Real Developer ID signing: enable Hardened Runtime (required for
  # notarization; Library Validation passes because everything is signed
  # with the same team).
  EXTRA_SETTINGS+=(
    "CODE_SIGN_STYLE=Manual"
    "CODE_SIGN_IDENTITY=$BRISKEDIT_SIGN_IDENTITY"
    "CODE_SIGNING_REQUIRED=YES"
    "ENABLE_HARDENED_RUNTIME=YES"
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
trap 'rm -rf "$STAGE"' EXIT

build_plain_dmg() {
  # GUI-free fallback: a plain drag-install DMG via hdiutil. No styled layout,
  # but a valid installable image that never depends on Finder/AppleScript.
  echo "note: building a plain DMG via hdiutil" >&2
  cp -R dist/BriskEdit.app "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  hdiutil create -volname "BriskEdit ${BRISKEDIT_VERSION}" \
    -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
}

CREATE_DMG_HELP=""
[[ -n "$CREATE_DMG_BIN" ]] && CREATE_DMG_HELP="$("$CREATE_DMG_BIN" --help 2>&1 || true)"

if [[ "$CREATE_DMG_HELP" == *"--volname"* ]]; then
  # create-dmg/create-dmg (Homebrew formula): styled layout.
  cp -R dist/BriskEdit.app "$STAGE/"
  if ! "$CREATE_DMG_BIN" \
      --volname "BriskEdit ${BRISKEDIT_VERSION}" \
      --window-pos 200 120 \
      --window-size 540 360 \
      --icon-size 96 \
      --icon "BriskEdit.app" 150 180 \
      --app-drop-link 390 180 \
      --no-internet-enable \
      "$DMG" \
      "$STAGE" >/dev/null; then
    echo "warning: styled create-dmg failed — falling back to a plain DMG" >&2
    rm -f "$DMG"; rm -rf "$STAGE"; mkdir -p "$STAGE"
    build_plain_dmg
  fi
elif [[ "$CREATE_DMG_HELP" == *"--dmg-title"* ]]; then
  # sindresorhus/create-dmg (npm): emits "<App> <version>.dmg" next to the app.
  ( cd dist && "$CREATE_DMG_BIN" --overwrite --no-code-sign \
      --dmg-title="BriskEdit ${BRISKEDIT_VERSION}" BriskEdit.app . >/dev/null 2>&1 || true )
  produced="$(ls -t dist/BriskEdit*.dmg 2>/dev/null | head -n1 || true)"
  if [[ -n "$produced" && "$produced" != "$DMG" ]]; then
    mv "$produced" "$DMG"
  fi
  [[ -f "$DMG" ]] || build_plain_dmg
else
  build_plain_dmg
fi

if [[ ! -f "$DMG" ]]; then
  echo "error: DMG was not produced at $DMG" >&2
  exit 1
fi

hdiutil imageinfo "$DMG" >/dev/null
echo "Built $DMG"
