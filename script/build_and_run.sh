#!/usr/bin/env bash
# Build the BriskEdit Debug bundle and (optionally) launch it.
#
# Usage:
#   ./script/build_and_run.sh              # build + launch
#   ./script/build_and_run.sh build-only   # build, do not launch
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "error: xcodegen is required. Install with: brew install xcodegen" >&2
  exit 1
fi

xcodegen >/dev/null

DERIVED_DATA="$(mktemp -d)"
trap 'rm -rf "$DERIVED_DATA"' EXIT

xcodebuild \
  -project BriskEdit.xcodeproj \
  -scheme BriskEdit \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
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
