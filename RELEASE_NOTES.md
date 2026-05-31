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
