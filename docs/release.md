# Release Runbook

## Branches and channels

| Channel | Source | Trigger | App | Feed |
|---|---|---|---|---|
| Nightly | `dev` | every pull request merged into `dev`, once CI passes | **BriskEdit Nightly** (`com.johannesgrof.briskedit.nightly`) | `releases/download/nightly/appcast.xml` |
| Beta | `main` | signed tag `vX.Y.Z-beta.N` | BriskEdit (`com.johannesgrof.briskedit`) | moving `beta` release, combined appcast |
| Stable | `main` | signed tag `vX.Y.Z` | BriskEdit | `releases/latest/download/appcast.xml` |

- Feature and fix branches open pull requests against `dev`; `dev` requires the same `build` check as `main`. CI rejects pull requests into `main` unless they come from `dev` or a `hotfix/*` branch.
- A release is a pull request from `dev` into `main`, merged with a merge commit (never squash or rebase, or the branches diverge). Tag the merge commit on `main`.
- A hotfix goes to `main` through a `hotfix/*` pull request; merge `main` back into `dev` afterwards.
- Dependabot opens its pull requests against `dev`.

### Stable and beta

- Stable: tags such as `v0.6.0`, latest GitHub release, default Sparkle channel (no channel tag).
- Beta: tags such as `v0.6.1-beta.1`, versioned GitHub prereleases, opted into in Settings → Updates.
- Beta clients poll the moving `beta` release's combined appcast. It keeps the newest stable and beta items, so testers can advance to a newer stable build. Stable clients use `/releases/latest/download/appcast.xml` and never opt into beta items.
- Fresh beta binaries default to beta; a saved explicit channel preference wins.
- 0.6.0 targets macOS 15+, while Liquid Glass is available on macOS 26+. The appcast minimum OS is read from the built app's `LSMinimumSystemVersion`.

### Nightly

BriskEdit Nightly is a separate app that installs next to BriskEdit. Its identity comes from build-setting overrides in `script/package_dmg.sh` (`BRISKEDIT_UPDATE_CHANNEL=nightly`), not from a separate target:

- Bundle identifier `com.johannesgrof.briskedit.nightly`, display name `BriskEdit Nightly`, icon `AppIconNightly.icon` (violet with a NIGHTLY ribbon, tuned for Light, Dark, Tinted and Clear).
- Info.plist `BriskEditDistribution=nightly` and `BriskEditSourceCommit=<short commit>`; `AppDistribution.current` reads them at runtime.
- Own state: `~/Library/Application Support/BriskEdit Nightly/Drafts`, its own preferences domain, and the shell commands `briskedit-nightly` and `brisk-nightly`. Themes stay shared.
- No channel picker and no automatic What's New. Settings → Updates offers a check cadence (every 15 minutes by default, hourly, daily) and automatic download and install (on by default). Sparkle never schedules checks more often than hourly; the 15-minute cadence adds background checks in between, and only while updates install automatically.
- Version `<MARKETING_VERSION>-nightly.<build>`, where build is `git rev-list --count` of the dev commit (for example `0.6.1-nightly.211`). The nightly app never compares against release build numbers, so a single monotonic integer is enough.
- Appcast items carry `<sparkle:channel>nightly</sparkle:channel>`; the nightly app allows only that channel, so a release build pointed at the feed would see nothing.

`.github/workflows/nightly.yml` starts on every push to `dev`, which is what merging a pull request into `dev` produces. One run has four jobs:

1. **CI** calls `.github/workflows/ci.yml` as a reusable workflow on the pushed commit (hygiene, secret scan, promo tooling, the full test suite). The unsigned package smoke test is skipped because the build job packages the real app, and the pull request already ran it. `ci.yml` itself only listens to pushes on `main`, so a merge into `dev` is tested once.
2. **Resolve** runs in parallel. It derives the identity with `script/nightly_identity.sh`, downloads the published nightly feed and asks `script/nightly_feed_decision.py`: publish only a build newer than the feed (`force` republishes the same build). It also skips when only `docs/`, `promo/`, `.github/assets/` or Markdown files changed since the previous nightly tag. A manual run must use `dev`.
3. **Build** on `macos-26`, in parallel with CI: package, sign (Developer ID), write notes with `script/nightly_release_notes.sh` (commits since the previous nightly), build the Sparkle ZIP and appcast, notarize and staple, verify the artifacts, and upload them as a workflow artifact. Signing secrets exist only in this job.
4. **Publish** on Ubuntu runs only when CI, Resolve and Build all succeeded. It checks the artifacts against `SHA256SUMS`, attests them, and updates the single rolling `nightly` prerelease (never latest): archive and DMG first, then `appcast.xml` and `SHA256SUMS`, then notes. It moves the `nightly` tag to the commit (a failure only warns), keeps the current and previous `BriskEdit-Nightly-<build>.zip`, deletes older archives, and verifies the published feed and archive byte for byte.

The concurrency group `nightly` runs one nightly at a time in push order and keeps only the newest pending run, so the feed only moves forward and a burst of merges publishes the newest commit. Expect a published nightly roughly 10 to 12 minutes after a merge (CI and the signed build run side by side for about 8 to 10 minutes, publishing takes about a minute); clients pick it up at their next check.

Pull requests merged by GitHub on behalf of a workflow token (Dependabot auto-merge) do not trigger workflows, so they ship with the next merged pull request or a manual run.

Assets on the `nightly` release: `BriskEdit-Nightly.dmg` (stable download link), `BriskEdit-Nightly-<build>.zip` (Sparkle), `appcast.xml`, `SHA256SUMS`.

### DMG design

Both DMGs use a styled Finder window (`create-dmg`, 660×440 background, icons at 170/210 and 490/210, volume icon from the app's `.icns`). Backgrounds live in `Config/DMG/background-{stable,nightly}.tiff` and are rendered by `script/render_dmg_background.swift` (see its header for the `tiffutil` step). Finder always draws labels in dark text on a picture background, even in Dark Mode, so the design stays light. Keep important content above y = 400: Finder's optional path bar covers the bottom of the window.

## Prerequisites

Developer ID signing, notarization and Sparkle Ed25519 signing are configured for published releases. The canonical public key is in `project.yml`; private signing and notarization material stays in GitHub secrets. Follow `script/verify_release_secrets.sh` for required secret names. Builds require Xcode 26 and the committed SwiftPM lock.

## Prepare and publish

1. Update the top `RELEASE_NOTES.md` section, `MARKETING_VERSION`, the derived `CURRENT_PROJECT_VERSION`, and both `WhatsNew.highlightsVersion` and `WhatsNew.sections` together. Run `script/prepare_xcode_project.sh`.
2. Run the full tests, `script/verify_release_metadata.sh`, `python3 -m unittest Tests/test_release_scripts.py`, actionlint and shellcheck. Land the release prep on `dev` like any other change, then open the release pull request from `dev` into `main` and wait for green CI.
3. Merge it with a merge commit, then create a **signed annotated tag** on that commit on main, for example `git tag -s v0.6.0 -m "BriskEdit 0.6.0"`, and push the tag. Do not publish unmerged code.
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

For example 0.6.0-beta.1 → 1006.0.1, 0.6.0 → 1006.0.99, 0.6.1-beta.1 → 1006.1.1. Versions are constrained to canonical minor/patch 0–99 and major 0–89 to respect Apple's four/two/two-digit build component limits. The project and local debug builds use the same derived identity, preventing a newer development version from offering an older production build as an update. Manual workflow `build` input is an optional equality check, not an override.

## Repair a failed nightly

- A failed nightly leaves the previous feed untouched: nothing is uploaded unless CI and the signed build both passed. The next pull request merged into `dev` publishes a newer build.
- To rebuild the tip of `dev` without a new merge, run the Nightly workflow on `dev` (Actions → Nightly → Run workflow). To republish the current build (for example after a GitHub outage), tick `force`. Clients that already installed that build are not offered it again; a real fix needs a new commit on `dev`.
- If the `nightly` release was edited by hand, keep it a prerelease and never mark it latest; the workflow refuses a non-prerelease `nightly` release.

## Repair a failed publication

Published versioned releases, tags, ZIPs and signatures are immutable. Fix a bad release with a new version; do not clobber the same build or move an old stable release to latest. An interrupted upload can resume while the release is still a draft. If publication succeeded but feed refresh failed, repair the feed using the existing signed artifacts after verifying them; do not rebuild/reissue the published version. Keep the old stable item until a verified replacement exists.
