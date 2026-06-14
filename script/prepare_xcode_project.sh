#!/usr/bin/env bash
# Generate the Xcode project and install the committed SwiftPM lock file into
# the generated workspace. Every xcodebuild invocation must then pass
# -onlyUsePackageVersionsFromResolvedFile to prevent dependency drift.
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "error: xcodegen is required. Install with: brew install xcodegen" >&2
  exit 1
fi

LOCK_SOURCE="$PWD/Config/Package.resolved"
LOCK_DEST="$PWD/BriskEdit.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"

if [[ ! -f "$LOCK_SOURCE" ]]; then
  echo "error: committed SwiftPM lock file is missing at $LOCK_SOURCE" >&2
  exit 1
fi

xcodegen >/dev/null
mkdir -p "$(dirname "$LOCK_DEST")"
cp "$LOCK_SOURCE" "$LOCK_DEST"
