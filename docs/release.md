# Release Runbook

End-to-end procedure for cutting a BriskEdit release.

## Channels

- **stable** — tags like `v0.2.0`. Published to the latest release, advertised on the public appcast.
- **beta** — tags like `v0.2.0-beta.1`. Published as a GitHub prerelease and a separate appcast feed users opt into in Settings → Updates.

The Sparkle controller filters channels via `allowedChannels(for:)` in `UpdateService`. Stable users never see beta entries.

## Prerequisites (one-time)

1. **Sparkle keys.** Generate once with the Sparkle `generate_keys` tool. Store:
   - Public key → repo secret `BRISKEDIT_SPARKLE_PUBLIC_KEY` and committed reference in `project.yml`'s Info.plist key `SUPublicEDKey`.
   - Private key → repo secret `BRISKEDIT_SPARKLE_PRIVATE_KEY`. Never committed, never logged.
2. **(later) Developer ID Application certificate** installed in the CI keychain.
3. **(later) Notarization credentials** stored as repo secrets `BRISKEDIT_NOTARY_APPLE_ID`, `BRISKEDIT_NOTARY_TEAM_ID`, `BRISKEDIT_NOTARY_PASSWORD`, `BRISKEDIT_NOTARY_ENABLED=true`.

## Per-release checklist

1. Update `RELEASE_NOTES.md` with the new section at the top.
2. Bump `MARKETING_VERSION` in `project.yml` and run `xcodegen`. For a reissued
   build of the same visible version, keep `MARKETING_VERSION` unchanged and use
   a higher Sparkle build number.
3. Open a PR, get a green CI run.
4. After merge, tag from `main`:
   ```bash
   git checkout main && git pull
   git tag -a v0.2.0 -m "BriskEdit 0.2.0"
   git push origin v0.2.0
   ```
   If a broken preview already used the same tag, delete the GitHub Release and
   remote tag first, then recreate the annotated tag from the fixed `main`
   commit. Do not leave assets built from one commit attached to a tag pointing
   at another commit.
5. The `release.yml` workflow runs:
   - regenerates the Xcode project
   - builds Release
   - packages a DMG (`script/package_dmg.sh`)
   - produces a signed Sparkle ZIP + appcast (`script/create_sparkle_assets.sh`)
   - verifies the appcast points at the right release URL
   - (when secrets are present) notarizes the DMG and staples the ticket
   - attaches everything to the GitHub Release
   Manual `workflow_dispatch` accepts an optional `build` input when a specific
   Sparkle build number is needed; otherwise it uses the GitHub run number.
6. Manually verify on a fresh machine:
   - Download the DMG.
   - Open, drag to Applications, launch.
   - Settings → Updates → Check Now → see the channel respond correctly.
7. Tweet / blog if it is a meaningful release.

## Beta cuts

Tag with `-beta.N`:

```bash
git tag -a v0.3.0-beta.1 -m "BriskEdit 0.3.0 beta 1"
git push origin v0.3.0-beta.1
```

The release workflow detects the suffix and:

- marks the GitHub Release as a prerelease,
- publishes the appcast under a moving `beta` release alias so beta-channel users get the feed continuously.

## Rollback

If a release is broken in the wild:

1. Delete or unpublish the GitHub Release.
2. Re-run the previous tag's release workflow with `workflow_dispatch` to restore the appcast pointer to the last good build.
3. Communicate the rollback in `RELEASE_NOTES.md` so the next release's notes acknowledge it.

Do **not** force-push tags. Once an appcast entry has been signed and downloaded by users, the version is immutable from their perspective.
