#!/usr/bin/env bash
# Build the BriskEdit Debug bundle and (optionally) launch it.
#
# Usage:
#   ./script/build_and_run.sh              # build + launch
#   ./script/build_and_run.sh build-only   # build, do not launch
set -euo pipefail

cd "$(dirname "$0")/.."

# A previously installed build can otherwise stay frontmost while the freshly
# built bundle launches behind it, making verification appear to use stale code.
pkill -x BriskEdit 2>/dev/null || true

./script/prepare_xcode_project.sh

DERIVED_DATA="$(mktemp -d)"
trap 'rm -rf "$DERIVED_DATA"' EXIT

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

# Copy into dist/ so it is inspectable after the script exits
mkdir -p dist
rm -rf dist/BriskEdit.app
cp -R "$APP_PATH" dist/BriskEdit.app
echo "Built dist/BriskEdit.app"

if [[ "${1:-}" == "build-only" ]]; then
  exit 0
fi

open dist/BriskEdit.app
