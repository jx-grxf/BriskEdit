#!/usr/bin/env bash
# Write release notes for a nightly build: a `## <version>` section whose bullets
# list the pull requests merged into dev since the previous nightly (or since the
# last release, for the first nightly after one). create_sparkle_assets.sh turns
# the bullets into the update dialog summary; the GitHub release shows the file.
#
# Usage: nightly_release_notes.sh <previous-commit-or-empty> <commit> <version> <output> [base-commit] [base-tag]
set -euo pipefail

cd "$(dirname "$0")/.."

usage="usage: nightly_release_notes.sh <previous-commit-or-empty> <commit> <version> <output> [base-commit] [base-tag]"
previous="${1-}"
commit="${2:?$usage}"
version="${3:?$usage}"
output="${4:?$usage}"
base_commit="${5-}"
base_tag="${6-}"
limit=40

if [[ -n "$previous" ]] && git merge-base --is-ancestor "$previous" "$commit" 2> /dev/null; then
  since="$previous"
  heading="Changes since the previous nightly"
elif [[ -n "$base_commit" ]] && git merge-base --is-ancestor "$base_commit" "$commit" 2> /dev/null; then
  # First nightly after a release, or the nightly tag no longer sits on dev.
  since="$base_commit"
  heading="Changes since ${base_tag:-the last release}"
else
  since=""
  heading="Recent changes"
fi

if [[ -n "$since" ]]; then
  range=("${since}..${commit}")
else
  range=("$commit")
fi

# One bullet per merged pull request: first-parent commits are the merges (or
# squashes) that landed on dev. A merge commit's subject is boilerplate, so use
# the pull request title GitHub puts in its body.
changes() {
  local sha subject title number
  while read -r sha; do
    subject="$(git log -1 --format=%s "$sha")"
    if [[ "$subject" =~ ^Merge\ pull\ request\ \#([0-9]+)\ from ]]; then
      number="${BASH_REMATCH[1]}"
      title="$(git log -1 --format=%b "$sha" | sed -n '/./{p;q;}')"
      printf -- '- %s (#%s)\n' "${title:-$subject}" "$number"
    else
      printf -- '- %s\n' "$subject"
    fi
  done < <(git rev-list --first-parent --max-count="$limit" "${range[@]}")
}

total="$(git rev-list --count --first-parent "${range[@]}")"
built_at="$(TZ=UTC git show -s --format=%cd --date=format-local:'%Y-%m-%d %H:%M UTC' "$commit")"
short="$(git rev-parse --short=7 "$commit")"

{
  printf '## %s\n\n' "$version"
  # shellcheck disable=SC2016 # literal Markdown backticks, not command substitution
  printf 'Built from `dev` at %s (%s). Nightly builds are signed and notarized but not release-tested, and they may break.\n\n' "$short" "$built_at"
  printf 'BriskEdit Nightly installs next to BriskEdit, keeps its own settings and drafts, and updates itself in the background.\n\n'
  printf '### %s\n\n' "$heading"
  if [[ "$total" -eq 0 ]]; then
    printf -- '- No changes since the previous nightly\n'
  else
    changes
    if ((total > limit)); then
      printf -- '- …and %d more\n' "$((total - limit))"
    fi
  fi
} > "$output"
