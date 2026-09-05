<div align="center">

# BriskEdit

<img src=".github/assets/logo.png" width="140" height="140" alt="BriskEdit app icon" />

A native macOS text editor for developers. Built in SwiftUI and AppKit, not Electron. Keeps editing local, recovers unsaved drafts, and runs code with the toolchains already installed on your Mac.

[![CI](https://github.com/jx-grxf/BriskEdit/actions/workflows/ci.yml/badge.svg)](https://github.com/jx-grxf/BriskEdit/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/jx-grxf/BriskEdit?label=release)](https://github.com/jx-grxf/BriskEdit/releases/latest)
![Platform](https://img.shields.io/badge/platform-macOS%2015%2B-111111)
![Swift](https://img.shields.io/badge/swift-6.0-orange)
![License](https://img.shields.io/badge/license-MIT-blue)

[Download](https://github.com/jx-grxf/BriskEdit/releases/latest) · [Architecture](ARCHITECTURE.md) · [Release runbook](docs/release.md) · [Security](SECURITY.md) · [Roadmap](#roadmap)

</div>

> [!TIP]
> Built for the exact moment when you open VS Code to fix one typo and watch 2 GB of RAM disappear, an extension host crash a CPU core, and a folder index spin for thirty seconds. BriskEdit opens before your finger leaves the trackpad.

## What it does

- **Opens files instantly.** TextKit 2 NSTextView, no background indexing on launch. Large-file mode disables expensive live features; files above 128 MiB are rejected.
- **Workspace, not document soup.** Open a folder, tabs persist, sidebar shows the file tree, split panes when you want them.
- **Run code from a button.** `Run` discovers the right toolchain for the file (clang/gcc for C, swiftc for Swift, python3 for Python, node/deno for JS/TS, cargo for Rust, go for Go) and runs it in the integrated terminal. No tasks.json, no launch.json, no extension to install.
- **Integrated terminal that actually feels like Terminal.app.** SwiftTerm-backed, real zsh, multiple tabs, cwd follows the workspace root, kills cleanly.
- **Markdown preview as a split.** Live render, scroll sync, GFM, sanitized.
- **Find / replace that doesn't blink.** In-file regex, in-folder with `.gitignore` respected, Command Palette and a fuzzy Go-to-File palette (⌘P) for everything else.
- **Code intelligence from the tools you already have.** Completion and live diagnostics via the language servers on your box (clangd, sourcekit-lsp, gopls, pyright, rust-analyzer, typescript-language-server) — no marketplace, no install step. A zero-config `Check File` (⌘B) syntax-checks C/C++/Swift even without a server; errors and warnings surface in the status bar.
- **Stays out of your way.** Format-on-save with your installed formatter, session restore, and live reload when a file changes on disk.
- **Lives in macOS.** Native menus, Settings, Quick Look, and Sparkle updates. Liquid Glass on macOS 26 adapts to native materials on macOS 15.

The point is the absence of bloat. No telemetry, no account, no LSP extension marketplace, no electron, no second runtime. Just the editor and the tools you already have on the box.

## Showcase

<p align="center">
  <video src="https://github.com/user-attachments/assets/f99a059e-b621-41fd-88f9-8073c551e313" width="900" controls autoplay muted loop playsinline></video>
</p>
<p align="center">
  <a href="https://github.com/jx-grxf/BriskEdit/raw/main/.github/assets/briskedit-promo.mp4"><b>▶ Watch the demo</b></a>
</p>

### Screenshots

| Editor workspace |
|---|
| <img src=".github/assets/showcase.png" width="420" alt="BriskEdit editing a Swift file with the file tree, tabs, and integrated terminal" /> |

## Install

1. Download the latest `BriskEdit-<version>.dmg` from [GitHub Releases](https://github.com/jx-grxf/BriskEdit/releases/latest).
2. Open the DMG and drag `BriskEdit.app` into Applications.
3. Launch from Applications or `open -a BriskEdit`.
4. Published releases are Developer ID signed and notarized. Local ad-hoc previews have a different trust identity.

Version 0.6.0 requires macOS 15 or newer; the currently published 0.5.2 release requires macOS 26. No account, no cloud sync, no analytics, no backend.

## How `Run` works

The Run button reads the active document's language and walks a static toolchain table:

| Language | Detection | Toolchain |
|---|---|---|
| C / C++ | `.c .h .cpp .hpp .cc .mm` | `xcrun --find clang` → fallback `gcc`, build to a temp binary, exec it |
| Swift | `.swift` | `xcrun --find swift`, prefer `swift script.swift`; for SwiftPM projects, `swift run` from the package root |
| Python | `.py` | `python3` (or `python`) from `PATH` |
| JavaScript / TypeScript | `.js .mjs .cjs .ts .tsx` | `node` or `deno` if installed |
| Rust | `.rs` | `cargo run` if `Cargo.toml` is reachable, else `rustc` + exec |
| Go | `.go` | `go run` against the file or the enclosing package |
| Shell | `.sh .zsh .bash` | the matching interpreter from `PATH` |

No `tasks.json`, no per-project config required for the trivial cases. When something does need configuration (build flags, run args, env), it lives in a single `briskedit.run.json` at the workspace root — opt-in, not the default.

The toolchain discovery and exec live in `RunService`. The Run button only ever shells out on user action and surfaces its stdout/stderr in a dedicated terminal tab.

## Safety

- Open file tabs use filesystem watchers to detect external edits.
- No telemetry, no analytics, no remote evaluation.
- `Run` never executes on file save or autocomplete — only on the explicit button or `⌘R`.
- The integrated terminal runs the local shell and its configured environment.
- Workspace state and recent files use local app preferences. Recovery copies live in `~/Library/Application Support/BriskEdit/Drafts`.

## Build from source

```bash
git clone https://github.com/jx-grxf/BriskEdit.git
cd BriskEdit
brew install xcodegen
./script/prepare_xcode_project.sh
xcodebuild -project BriskEdit.xcodeproj -scheme BriskEdit -configuration Debug \
  -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates build
open ~/Library/Developer/Xcode/DerivedData/BriskEdit-*/Build/Products/Debug/BriskEdit.app
```

The `project.yml` is the source of truth — the `.xcodeproj` is generated and `.gitignored`. Regenerate after editing `project.yml`.

Run convenience:

```bash
./script/build_and_run.sh        # build + launch a debug bundle
./script/build_and_run.sh build-only
```

To package a local DMG:

```bash
BRISKEDIT_VERSION=0.6.0 ./script/package_dmg.sh
```

## Release pipeline

GitHub Actions builds tagged releases: app bundle, DMG, Sparkle ZIP and appcast, signature verification, notarization, and stapler validation. Full runbook in [docs/release.md](docs/release.md). Public release notes live in [RELEASE_NOTES.md](RELEASE_NOTES.md).

Distribution roadmap:

- Developer ID signing and notarization shipped with 0.5.2.
- Homebrew Cask submission after the first notarized release.

## New in the 0.6.0 source tree

- Recover unsaved drafts, including untitled files, as safe copies after unexpected exits.
- Compare editor content with disk; review staged and unstaged Git diffs.
- Find References through installed language servers.
- Navigate tabs with ⇧⌘[ and ⇧⌘]; reopen closed tabs with ⇧⌘T.
- Use macOS 15+, with availability-guarded Liquid Glass on macOS 26.

Recovery is local and optional (Settings → General). Limits: 2 MiB per draft, 20 drafts / 20 MiB total, retained up to 14 days. It is a recovery aid, not a replacement for saving or backups. Oversized buffers are not snapshotted. The release workflow publishes only after the signed tag, tests, signing, notarization and feed checks pass.

## Roadmap

Next candidates are richer Git hunk review, safe LSP rename/code actions with edit preview, and additional language grammars. There is no extension marketplace, required account, cloud sync, or built-in AI-completion engine.

## Tech stack

SwiftUI · AppKit (`NSTextView` with TextKit 2, a separate sibling gutter) · macOS 15+ · `@Observable` · Swift 6 strict concurrency · Swift Package Manager (consumed via Xcode) · `xcodegen` for project generation · GitHub Actions on macOS · Sparkle for updates · SwiftTerm for the integrated terminal · WKWebView Markdown preview · Neon/SwiftTreeSitter for Swift and JSON syntax.

## Contributing

Issues and focused pull requests welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md), keep changes scoped, run the build before opening a PR. Security reports go through [SECURITY.md](SECURITY.md).

## License

MIT. See [LICENSE](LICENSE).
Johannes Grof - 2026
