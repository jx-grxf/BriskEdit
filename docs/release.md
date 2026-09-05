# Release Runbook

## Channels and compatibility

- Stable: tags such as `v0.6.0`, latest GitHub release, default Sparkle channel (no channel tag).
- Beta: tags such as `v0.6.1-beta.1`, versioned GitHub prereleases, opted into in Settings → Updates.
- Beta clients poll the moving `beta` release's combined appcast. It keeps the newest stable and beta items, so testers can advance to a newer stable build. Stable clients use `/releases/latest/download/appcast.xml` and never opt into beta items.
- Fresh beta binaries default to beta; a saved explicit channel preference wins.
- 0.6.0 targets macOS 15+, while Liquid Glass is available on macOS 26+. The appcast minimum OS is read from the built app's `LSMinimumSystemVersion`.

## Prerequisites

Developer ID signing, notarization and Sparkle Ed25519 signing are configured for published releases. The canonical public key is in `project.yml`; private signing and notarization material stays in GitHub secrets. Follow `script/verify_release_secrets.sh` for required secret names. Builds require Xcode 26 and the committed SwiftPM lock.

## Prepare and publish

1. Update the top `RELEASE_NOTES.md` section, `MARKETING_VERSION`, and both `WhatsNew.highlightsVersion` and `WhatsNew.sections` together. Run `script/prepare_xcode_project.sh`.
2. Run the full tests, `script/verify_release_metadata.sh`, `python3 -m unittest Tests/test_release_scripts.py`, actionlint and shellcheck; open a PR and wait for green CI.
3. After merge, create a **signed annotated tag** on main, for example `git tag -s v0.6.0 -m "BriskEdit 0.6.0"`, then push that tag. Do not publish unmerged code.
4. Release preflight verifies the tag signature and main ancestry. It rejects an already published version and releases that would move their channel backwards. Unpublished drafts can be retried.
5. The workflow builds/tests the tagged source, packages/signs/notarizes the artifacts, and verifies version identity, archive length and the archive's Ed25519 signature against the bundle public key.
6. Assets upload to a draft first. Only the complete release is published; stable is marked latest and beta is explicitly not latest.
7. The combined beta feed merges the current release, current stable feed and previous combined feed. Fetch failures other than a missing optional feed abort. Each retained enclosure is downloaded and signature-verified before the moving beta feed is replaced.
8. Test a clean installation and a Sparkle update from 0.5.2 on a real Mac. Exercise stable → newer stable, beta → newer beta, beta → newer stable, and channel switching. No downgrade is offered merely by selecting Stable.

## Build identity

`script/release_build_number.sh VERSION` derives a numeric three-component CFBundleVersion, also used as `sparkle:version`:

- First component: `1000 + major × 100 + minor`. The epoch is above legacy GitHub-run build numbers (0.5.2 shipped build 19).
- Second component: patch.
- Third component: beta ordinal 1–98, or 99 for stable.

For example 0.6.0-beta.1 → 1006.0.1, 0.6.0 → 1006.0.99, 0.6.1-beta.1 → 1006.1.1. Versions are constrained to canonical minor/patch 0–99 and major 0–89 to respect Apple's four/two/two-digit build component limits. Local debug builds may retain project build 1. Manual workflow `build` input is an optional equality check, not an override.

## Repair a failed publication

Published versioned releases, tags, ZIPs and signatures are immutable. Fix a bad release with a new version; do not clobber the same build or move an old stable release to latest. An interrupted upload can resume while the release is still a draft. If publication succeeded but feed refresh failed, repair the feed using the existing signed artifacts after verifying them; do not rebuild/reissue the published version. Keep the old stable item until a verified replacement exists.
