#!/usr/bin/env bash
# Derive the nightly build identity for a commit on dev. Prints key=value lines
# suitable for $GITHUB_OUTPUT:
#   commit        full commit id
#   short_commit  seven-character id, stamped into Info.plist
#   build         commits reachable from the commit; dev only moves forward, so
#                 this is monotonic and serves as CFBundleVersion/sparkle:version
#   version       <MARKETING_VERSION at that commit>-nightly.<build>
#
# The nightly app has its own bundle identifier and feed, so its single-integer
# build never competes with the release build numbers (1006.1.99 and so on).
set -euo pipefail

cd "$(dirname "$0")/.."

ref="${1:?usage: nightly_identity.sh <commit>}"
commit="$(git rev-parse --verify "${ref}^{commit}")"
build="$(git rev-list --count "$commit")"
[[ "$build" =~ ^[1-9][0-9]{0,3}$ ]] || {
  echo "error: nightly build '$build' does not fit a four-digit CFBundleVersion" >&2
  exit 1
}

project_version="$(git show "${commit}:project.yml" | awk -F'"' '/MARKETING_VERSION:/ { print $2; exit }')"
[[ "$project_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-beta\.[0-9]+)?$ ]] || {
  echo "error: MARKETING_VERSION '$project_version' at $commit is not a supported version" >&2
  exit 1
}

printf 'commit=%s\n' "$commit"
printf 'short_commit=%s\n' "$(git rev-parse --short=7 "$commit")"
printf 'build=%s\n' "$build"
printf 'version=%s-nightly.%s\n' "$project_version" "$build"
