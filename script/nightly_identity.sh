#!/usr/bin/env bash
# Derive the nightly build identity for a commit on dev. Prints key=value lines
# suitable for $GITHUB_OUTPUT:
#   commit        full commit id
#   short_commit  seven-character id, stamped into Info.plist
#   build         commits reachable from the commit. dev only moves forward, so
#                 this is monotonic and serves as CFBundleVersion/sparkle:version.
#                 It is an internal ordering number and is not shown in the app.
#   sequence      nightlies since the last release: first-parent commits (one per
#                 merged pull request) after the commit that release shipped
#   version       <next release>-nightly.<sequence>, the version users see —
#                 "0.6.2-nightly.3" reads as the third nightly on the way to 0.6.2
#   base_tag      release the sequence counts from (empty before the first release)
#   base_commit   dev commit that release shipped from (empty likewise)
#
# The nightly app has its own bundle identifier and feed, so `build` never
# competes with the release build numbers (1006.1.99 and so on).
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

# Newest release tag, ranked by the numeric build the release derives from, so
# v0.7.0 beats v0.7.0-beta.9 and v0.10.0 beats v0.9.0.
base_tag=""
base_rank=-1
while read -r tag; do
  [[ -n "$tag" ]] || continue
  number="$(./script/release_build_number.sh "${tag#v}" 2> /dev/null)" || continue
  rank="$(awk -F. '{ print $1 * 10000 + $2 * 100 + $3 }' <<< "$number")"
  if [[ "$rank" -gt "$base_rank" ]]; then
    base_rank="$rank"
    base_tag="$tag"
  fi
done < <(git tag --list 'v*')

# Release tags sit on main's merge commit; the dev commit that release shipped
# is their merge base, and counting first parents from there gives one number
# per merged pull request.
base_commit=""
sequence="$build"
if [[ -n "$base_tag" ]]; then
  base_commit="$(git merge-base "$base_tag" "$commit" 2> /dev/null || true)"
  if [[ -n "$base_commit" ]]; then
    sequence="$(git rev-list --count --first-parent "${base_commit}..${commit}")"
  fi
fi

# Nightlies lead to the next release: the version dev carries while it is still
# unreleased, otherwise the next patch. A -beta suffix drops out, because betas
# and nightlies lead to the same stable version.
next_version="${project_version%%-*}"
if [[ "$project_version" == "$next_version" ]] \
  && git rev-parse -q --verify "refs/tags/v${project_version}^{commit}" > /dev/null; then
  IFS=. read -r major minor patch <<< "$next_version"
  next_version="${major}.${minor}.$((patch + 1))"
fi

printf 'commit=%s\n' "$commit"
printf 'short_commit=%s\n' "$(git rev-parse --short=7 "$commit")"
printf 'build=%s\n' "$build"
printf 'sequence=%s\n' "$sequence"
printf 'version=%s-nightly.%s\n' "$next_version" "$sequence"
printf 'base_tag=%s\n' "$base_tag"
printf 'base_commit=%s\n' "$base_commit"
