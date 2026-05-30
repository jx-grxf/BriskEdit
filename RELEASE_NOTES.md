# Release Notes

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
