# Release Notes

## 0.3.5 — Signature help, inline diagnostics, and a silent-crash fix

Builds on 0.3.4. Still an unsigned developer preview — on first launch, right-click
`BriskEdit.app` → **Open** → confirm.

### Added

- **Signature help.** Typing inside a call shows a floating parameter-hint panel
  with the active argument highlighted, driven by the language server and a
  buffer-local fallback when the server is still recovering from broken code.
- **Inline diagnostics.** Errors and warnings are underlined with wavy squiggles
  that track the text as you type, with details on hover.

### Fixed

- **Fixed the editor silently quitting while typing in C files.** Writing to a
  language server (clangd) that had already closed its pipe raised `SIGPIPE`,
  which terminates the whole app with no crash report — so the window just
  vanished. `SIGPIPE` is now ignored from process start, before any pipe exists,
  so a dead subprocess can never take the app down.
- Hardened the LSP client against half-started and dead servers: concurrent cold
  starts now share one start task, and writes to a failed server fail gracefully
  instead of crashing.

### Compatibility

- macOS 26 (Tahoe) or later, Apple silicon.

## 0.3.4 — Formatter memory safety hardening

A critical stability release on top of 0.3.3. Still an unsigned developer preview — on
first launch, right-click `BriskEdit.app` → **Open** → confirm.

### Fixed

- **Fixed the remaining Format Document memory runaway.** Clang-format project
  configuration discovery now uses a bounded, cycle-safe lexical parent walk
  instead of an unbounded Foundation URL loop.
- All formatter entry points now share one global single-flight gate, including
  manual formatting and format-on-save.
- Formatter processes now have strict input, output, and execution-time limits;
  stdout and stderr are drained concurrently to prevent pipe deadlocks.
- Stale format-on-save results are discarded when the document changes before
  formatting completes.

### Improved

- Git, diagnostics, tool discovery, and installer processes now use bounded
  output capture and timeouts.
- Oversized editor files, LSP messages, Discord IPC frames, Markdown previews,
  and search buffers are capped to keep memory use predictable under malformed
  or unexpectedly large input.
- Formatter telemetry now records duration, input size, and suppressed duplicate
  requests for future incident diagnosis.

### Compatibility

Requires macOS 26 or newer. Xcode 26+ to build from source.
