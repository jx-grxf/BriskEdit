#!/usr/bin/env bash
# Write release notes for a nightly build: a `## Nightly <build>` section whose
# bullets list the commits since the previous nightly. create_sparkle_assets.sh
# turns the bullets into the update dialog summary; the GitHub release shows the
# whole file.
#
# Usage: nightly_release_notes.sh <previous-commit-or-empty> <commit> <build> <output>
set -euo pipefail

cd "$(dirname "$0")/.."

previous="${1-}"
commit="${2:?usage: nightly_release_notes.sh <previous-commit-or-empty> <commit> <build> <output>}"
build="${3:?usage: nightly_release_notes.sh <previous-commit-or-empty> <commit> <build> <output>}"
output="${4:?usage: nightly_release_notes.sh <previous-commit-or-empty> <commit> <build> <output>}"
limit=40

if [[ -n "$previous" ]] && git merge-base --is-ancestor "$previous" "$commit" 2>/dev/null; then
  range=("${previous}..${commit}")
  heading="Changes since the previous nightly"
else
  # First nightly, or the previous tag is no longer on dev's history.
  range=("$commit")
  heading="Recent changes"
fi

total="$(git rev-list --count --no-merges "${range[@]}")"
built_at="$(TZ=UTC git show -s --format=%cd --date=format-local:'%Y-%m-%d %H:%M UTC' "$commit")"
short="$(git rev-parse --short=7 "$commit")"

{
  printf '## Nightly %s\n\n' "$build"
  # shellcheck disable=SC2016 # literal Markdown backticks, not command substitution
  printf 'Built from `dev` at %s (%s). Nightly builds are signed and notarized but not release-tested, and they may break.\n\n' "$short" "$built_at"
  printf 'BriskEdit Nightly installs next to BriskEdit, keeps its own settings and drafts, and updates itself in the background.\n\n'
  printf '### %s\n\n' "$heading"
  if [[ "$total" -eq 0 ]]; then
    printf -- '- No code changes since the previous nightly\n'
  else
    git log --no-merges --max-count="$limit" --format='- %s (%h)' "${range[@]}"
    if (( total > limit )); then
      printf -- '- …and %d more commits\n' "$((total - limit))"
    fi
  fi
} > "$output"
