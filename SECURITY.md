# Security Policy

BriskEdit runs entirely on the local machine. It does not send telemetry, analytics, or document contents anywhere, and it does not require an account. The trust boundaries that matter are: the integrity of the downloaded app bundle, the Sparkle update channel, and the integrated terminal / Run pipeline.

## Reporting a Vulnerability

Report security issues through GitHub:

- **Preferred — private report:** open the repository's **Security** tab and choose **“Report a vulnerability”** (GitHub private vulnerability reporting). This keeps the details confidential until a fix ships.
- **Otherwise — open an issue:** if private reporting is unavailable to you, open a [GitHub issue](https://github.com/jx-grxf/BriskEdit/issues). In that case describe the impact but **do not include a working exploit or sensitive details** in the public thread — note that you have them and they will be requested privately.

A response within 72 hours is the target. If a fix is shipped, the release notes will credit the reporter unless they request otherwise.

## Scope

In scope:

- Arbitrary code execution via a crafted file opened in the editor.
- Arbitrary code execution via the Run pipeline (toolchain resolution, environment leaking).
- Sparkle update channel tampering, signature bypass, or downgrade attacks.
- Path traversal, symlink, or quarantine escapes during open / save / DMG mount.
- Privilege escalation outside of what the app's signing entitlements grant.

Out of scope (for now):

- Issues that require root or physical access.
- Denial of service via deliberately huge files — known limitation, tracked separately.
- Third-party dependencies (Sparkle, SwiftTerm, swift-markdown) — report those upstream and we will pull the patched version once it lands.

## Update Channel Integrity

- The appcast is signed with an Ed25519 key. The matching public key is embedded in `Info.plist` (`SUPublicEDKey`) and verified by Sparkle on every update check.
- The private key never leaves CI secret storage and the maintainer's local keychain.
- The download URLs in the appcast point at GitHub Releases on the canonical repository (`github.com/jx-grxf/BriskEdit`). Any deviation from that prefix is a release-pipeline bug to report.

## Hardening

- `ENABLE_HARDENED_RUNTIME = YES` for release builds.
- No `com.apple.security.cs.disable-library-validation` entitlement.
- Sandbox: not currently enabled (the editor needs to open arbitrary user-chosen paths and execute the Run command). The plan is to enable App Sandbox with `com.apple.security.files.user-selected.read-write` once the Run pipeline is auditable.
