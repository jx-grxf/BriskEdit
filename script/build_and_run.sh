#!/usr/bin/env bash
# Build the BriskEdit Debug bundle and (optionally) launch it.
#
# Usage:
#   ./script/build_and_run.sh              # build + launch
#   ./script/build_and_run.sh build-only   # build, do not launch
set -euo pipefail

cd "$(dirname "$0")/.."

./script/prepare_xcode_project.sh

DERIVED_DATA="${BRISKEDIT_DERIVED_DATA:-$PWD/.build/local-debug}"

xcodebuild \
  -project BriskEdit.xcodeproj \
  -scheme BriskEdit \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  -onlyUsePackageVersionsFromResolvedFile \
  -skipPackageUpdates \
  build | tail -20

APP_PATH="$DERIVED_DATA/Build/Products/Debug/BriskEdit.app"

if [[ ! -d "$APP_PATH" ]]; then
  echo "error: build succeeded but $APP_PATH does not exist" >&2
  exit 1
fi

# Only an actual relaunch asks the running app to quit, through its normal
# Save/Discard/Cancel flow. A failed build or build-only never stops the editor.
if [[ "${1:-}" != "build-only" ]] && pgrep -x BriskEdit >/dev/null; then
  if ! osascript -e 'tell application id "com.johannesgrof.briskedit" to quit'; then
    echo "The build succeeded; relaunch was cancelled. The running editor was kept." >&2
    exit 1
  fi
  for _ in {1..50}; do
    if ! pgrep -x BriskEdit >/dev/null; then break; fi
    sleep 0.1
  done
  if pgrep -x BriskEdit >/dev/null; then
    echo "The build succeeded; BriskEdit is still running, so relaunch was skipped." >&2
    exit 1
  fi
fi

# Copy into dist/ so it is inspectable after the script exits
mkdir -p dist
rm -rf dist/BriskEdit.app
cp -R "$APP_PATH" dist/BriskEdit.app
echo "Built dist/BriskEdit.app"

if [[ "${1:-}" == "build-only" ]]; then
  exit 0
fi

open dist/BriskEdit.app
