# Release Notes

## 0.2.0 — multi-session terminal & editor stability

Still an unsigned developer preview — on first launch, right-click `BriskEdit.app`
→ **Open** → confirm. Developer ID notarization is queued for a later release.

### New

- **Multi-session terminal.** A VS Code-style session list — add, switch between,
  and close multiple shells. Each `New Shell` starts a genuinely fresh shell
  (screen, scrollback and terminal modes reset, cursor re-shown).
- **Configurable terminal font.** New Terminal settings tab; defaults to
  MesloLGS Nerd Font 14 with family-name resolution.
- **Workspace-aware shells.** The active shell restarts in the new folder when the
  workspace root changes.

### Fixed

- **Editor no longer jumps or overscrolls.** The text view is only reconfigured
  and re-highlighted on theme or external buffer changes instead of on every
  keystroke — the per-edit relayout had briefly mis-measured the viewport and
  slid the line numbers off-screen.
- **Gutter stays painted.** Line numbers repaint on every layout pass and skip
  (then reschedule) a paint while the viewport reports zero height, so they no
  longer get stuck blank after a tab switch, restored session, or window
  activation.
- **Dotfiles in the file tree.** Meaningful dotfiles (`.github`, `.gitignore`, …)
  show by default; the **Hidden** toggle now also reveals build/dependency output.
- **Source Control empty state** is pinned to full height, so the pane header
  stays at the top instead of being vertically centered.
- **Terminal polish.** Resize lag/flicker gone (transient drag state, layer-backed
  opaque view); the blinking caret is restored after `Ctrl-C` out of a TUI.
- **In-app updates.** The Sparkle public key is embedded by default, so the
  updater starts reliably across builds.

### Compatibility

Requires macOS 26 or newer. Xcode 26+ to build from source.

## 0.1.1 — first public preview

Same feature set as 0.1.0, with the launch fixed. 0.1.0 could not start because
Hardened Runtime enforced Library Validation against the ad-hoc signature — the
bundled Sparkle framework failed to load. Hardened Runtime is now off for the
unsigned preview (it returns once Developer ID signing + notarization land).

An unsigned developer preview — on first launch, right-click `BriskEdit.app` →
**Open** → confirm. Developer ID notarization is queued for a later release.

### What works

- **Instant editor.** TextKit 2 `NSTextView`, no launch-time indexing. Large files open without freezing the UI.
- **Workspace.** Open a folder, file-tree sidebar, persistent tabs, session restore for the primary window, multi-window support.
- **Gutter.** Line numbers, live git change bars (added / modified / deleted), and inline diagnostics markers — drawn by a TextKit 2-native gutter.
- **Source Control sidebar.** Branch switch / create, fetch · pull · push with ahead/behind counts, stage / unstage / discard, and a commit box — all through your own `git`.
- **Run from a button.** Detects the toolchain for the active file (clang/gcc, swiftc/SwiftPM, python3, node/deno, cargo/rustc, go) and runs it in the integrated terminal. No `tasks.json`.
- **Integrated terminal.** SwiftTerm-backed, real zsh, cwd follows the workspace root, terminated cleanly on quit.
- **Markdown preview** as a live, scroll-synced, sanitized split.
- **Code intelligence from installed tools.** Completion and live diagnostics via the language servers already on your machine (clangd, sourcekit-lsp, gopls, pyright, rust-analyzer, typescript-language-server). Rich completion popup with kind badges and signatures. A zero-config `Check File` (⌘B) syntax-checks C/C++/Swift without a server. Servers are terminated on quit and on tab close.
- **Find / replace** in-file (regex) and in-folder (respecting `.gitignore`), Command Palette (⇧⌘P) and fuzzy Go-to-File (⌘P).
- **Format-on-save** with your installed formatter, optional after-delay autosave, and live reload when a file changes on disk.
- **Native macOS.** Menus, Settings scene, Quick Look / PDF preview hosts, Sparkle updates with stable / beta channels.

### Known gaps

- No syntax highlighting theme engine yet (Tree-sitter is on the roadmap).
- Multi-cursor and column selection are not implemented.
- The app is not yet notarized; Gatekeeper requires the right-click → Open step on first launch.

### Compatibility

Requires macOS 26 or newer. Xcode 26+ to build from source.

## 0.1.0 — first public preview

The first public build of BriskEdit. An unsigned developer preview — on first launch, right-click `BriskEdit.app` → **Open** → confirm. Developer ID notarization is queued for a later release.

### What works

- **Instant editor.** TextKit 2 `NSTextView`, no launch-time indexing. Large files open without freezing the UI.
- **Workspace.** Open a folder, file-tree sidebar, persistent tabs, session restore for the primary window, multi-window support.
- **Gutter.** Line numbers, live git change bars (added / modified / deleted), and inline diagnostics markers — drawn by a TextKit 2-native gutter.
- **Source Control sidebar.** Branch switch / create, fetch · pull · push with ahead/behind counts, stage / unstage / discard, and a commit box — all through your own `git`.
- **Run from a button.** Detects the toolchain for the active file (clang/gcc, swiftc/SwiftPM, python3, node/deno, cargo/rustc, go) and runs it in the integrated terminal. No `tasks.json`.
- **Integrated terminal.** SwiftTerm-backed, real zsh, cwd follows the workspace root, terminated cleanly on quit.
- **Markdown preview** as a live, scroll-synced, sanitized split.
- **Code intelligence from installed tools.** Completion and live diagnostics via the language servers already on your machine (clangd, sourcekit-lsp, gopls, pyright, rust-analyzer, typescript-language-server). Rich completion popup with kind badges and signatures. A zero-config `Check File` (⌘B) syntax-checks C/C++/Swift without a server. Servers are terminated on quit and on tab close.
- **Find / replace** in-file (regex) and in-folder (respecting `.gitignore`), Command Palette (⇧⌘P) and fuzzy Go-to-File (⌘P).
- **Format-on-save** with your installed formatter, optional after-delay autosave, and live reload when a file changes on disk.
- **Native macOS.** Menus, Settings scene, Quick Look / PDF preview hosts, Sparkle updates with stable / beta channels.

### Known gaps

- No syntax highlighting theme engine yet (Tree-sitter is on the roadmap).
- Multi-cursor and column selection are not implemented.
- The app is not yet notarized; Gatekeeper requires the right-click → Open step on first launch.

### Compatibility

Requires macOS 26 or newer. Xcode 26+ to build from source.

### Verification before tagging

- `xcodegen && xcodebuild -scheme BriskEdit -configuration Release build` succeeds.
- `codesign --verify --deep --strict` on the resulting `.app` returns clean.
- DMG mounts and the app launches from `/Applications` after the drag.
