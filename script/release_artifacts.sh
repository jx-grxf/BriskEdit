#!/usr/bin/env bash
# Print one artifact name for the selected update channel, so packaging,
# notarization, verification and publishing agree on every path.
#
# Usage: release_artifacts.sh <app-name|app-bundle|bundle-id|dmg|zip>
#
# Inputs (env):
#   BRISKEDIT_UPDATE_CHANNEL   stable (default), beta or nightly
#   BRISKEDIT_VERSION          required for stable/beta dmg and zip names
#   BRISKEDIT_BUILD            required for the nightly zip name
set -euo pipefail

field="${1:?usage: release_artifacts.sh <app-name|app-bundle|bundle-id|dmg|zip>}"
channel="${BRISKEDIT_UPDATE_CHANNEL:-stable}"

case "$channel" in
  stable | beta)
    app_name="BriskEdit"
    bundle_id="com.johannesgrof.briskedit"
    ;;
  nightly)
    # A separate app that installs next to a release: own name, identifier,
    # icon and feed. The DMG name never changes so its download link is stable.
    app_name="BriskEdit Nightly"
    bundle_id="com.johannesgrof.briskedit.nightly"
    ;;
  *)
    echo "error: update channel must be stable, beta or nightly" >&2
    exit 1
    ;;
esac

case "$field" in
  app-name)
    printf '%s\n' "$app_name"
    ;;
  app-bundle)
    printf '%s.app\n' "$app_name"
    ;;
  bundle-id)
    printf '%s\n' "$bundle_id"
    ;;
  dmg)
    if [[ "$channel" == "nightly" ]]; then
      printf 'BriskEdit-Nightly.dmg\n'
    else
      printf 'BriskEdit-%s.dmg\n' "${BRISKEDIT_VERSION:?BRISKEDIT_VERSION is required}"
    fi
    ;;
  zip)
    if [[ "$channel" == "nightly" ]]; then
      printf 'BriskEdit-Nightly-%s.zip\n' "${BRISKEDIT_BUILD:?BRISKEDIT_BUILD is required}"
    else
      printf 'BriskEdit-%s.zip\n' "${BRISKEDIT_VERSION:?BRISKEDIT_VERSION is required}"
    fi
    ;;
  *)
    echo "error: unknown artifact field '$field'" >&2
    exit 1
    ;;
esac
