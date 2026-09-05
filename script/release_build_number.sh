#!/usr/bin/env bash
# A three-component CFBundleVersion: epoch+major/minor, patch, release stage.
# Epoch 1000 is above every legacy GitHub-run build (latest shipped build: 19).
# Stay within Apple's four/two/two-digit component limits. Stable sorts after
# all betas of its version and before the next patch/minor/major prerelease.
set -euo pipefail
version="${1:?usage: release_build_number.sh <semver>}"
if [[ ! "$version" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)(-beta\.([0-9]+))?$ ]]; then
  echo "error: unsupported release version '$version'" >&2
  exit 1
fi
major="${BASH_REMATCH[1]}" minor="${BASH_REMATCH[2]}" patch="${BASH_REMATCH[3]}"
stage="${BASH_REMATCH[5]:-99}"
# Reject noncanonical leading zeros before shell arithmetic.
for component in "$major" "$minor" "$patch" "$stage"; do
  [[ "$component" =~ ^(0|[1-9][0-9]?)$ ]] || { echo "error: version components must be canonical 0...99" >&2; exit 1; }
done
if [[ "$version" == *-beta.* ]]; then
  (( stage >= 1 && stage <= 98 )) || { echo "error: beta ordinal must be 1...98" >&2; exit 1; }
fi
(( major <= 89 )) || { echo "error: major version exceeds this build-number epoch" >&2; exit 1; }
printf '%d.%d.%d\n' "$((1000 + major * 100 + minor))" "$patch" "$stage"
