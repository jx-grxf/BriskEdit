# Release Notes

## 0.4.0 - Faster editing, richer source control, and safer releases

BriskEdit 0.4.0 is a larger editor and tooling release. It remains an unsigned
developer preview; on first launch, right-click `BriskEdit.app`, choose **Open**,
and confirm.

### Added

- **Tree-sitter highlighting for Swift and JSON.** Compiled grammar
  configurations are cached, with instant fallback highlighting while a grammar
  warms up.
- **Low Power, Adaptive, and Power modes.** Background work responds to system
  power and thermal state; Power mode can prepare grammars ahead of first use.
- **A guided first-run experience.** Onboarding configures performance, theme,
  editor basics, and source control. A new welcome screen surfaces recent folders
  and common actions.
- **Richer source control context.** Inline blame, file-tree status badges,
  colored file icons, an activity-bar sidebar, and clickable breadcrumbs keep
  repository state visible without leaving the editor.
- **The `briskedit` command-line launcher.** An optional shorter `brisk` alias is
  installed only when that name is available.
- **An in-app What's New page** shown after updates.

### Improved

- **Large-file editing.** Expensive editor features ease off automatically above
  4 MB, with accurate line numbers and file-size reporting preserved.
- **Git refresh behavior.** Status scans are coalesced, paths with Unicode,
  newlines, and renames are parsed safely, and decorations refresh after saves.
- **Resource safety.** Formatter requests, subprocesses, watchers, debounce
  tasks, and per-tab LSP state are bounded and released predictably.
- **Reproducible builds.** Swift packages are locked to committed revisions and
  package updates are disabled during CI and release builds.

### Release Engineering

- CI now runs warnings-as-errors tests, a real DMG smoke build, shell and workflow
  linting, dependency review, Gitleaks history scanning, promo-tooling audit and
  type checks, and CodeQL analysis.
- Release jobs require a verified signed annotated tag reachable from `main`,
  retest the tagged source, validate DMG/ZIP/appcast metadata and signatures,
  publish SHA-256 checksums, and attach GitHub provenance attestations.
- Third-party GitHub Actions are pinned to immutable commits. Dependabot security
  updates, dependency review, secret scanning, and push protection are enabled.

### Compatibility

- macOS 26 (Tahoe) or later, Apple silicon.
