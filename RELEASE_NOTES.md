# Release Notes

## 0.3.6 — Terminal scroll in TUIs, Option-as-Meta, and editor indentation fixes

Builds on 0.3.5. Still an unsigned developer preview — on first launch, right-click
`BriskEdit.app` → **Open** → confirm.

### Added

- **Scroll wheel now works inside full-screen terminal apps.** The wheel and
  trackpad now scroll full-screen TUIs (Claude Code, htop, less) that run on the
  alternate screen. Mouse-reporting apps receive proper wheel events; others get
  cursor up/down. Normal-screen scrollback is unchanged.
- **Optional "Use Option as Meta key" for the terminal.** A new terminal setting
  (off by default) makes ⌥ act as the Meta modifier for Emacs-style shortcuts.
  Left off, ⌥ keeps producing layout characters — needed for `@`, `{`, `}`, `|`,
  `~` on international keyboards (e.g. German ⌥L = `@`).

### Fixed

- **Smart backspace in indented code.** In spaces mode, pressing Backspace inside
  a line's leading whitespace now removes a whole indent level back to the
  previous tab stop in one keystroke instead of one space at a time.
- **No more phantom indentation on blank lines.** Pressing Return while leaving a
  whitespace-only line trims its indentation, so blank lines no longer keep
  trailing spaces or copy a stale indent downward.

### Compatibility

- macOS 26 (Tahoe) or later, Apple silicon.
