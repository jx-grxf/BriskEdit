# Release Notes

## 0.3.3 — Emergency formatter memory fix

A critical fix release on top of 0.3.2. Still an unsigned developer preview — on
first launch, right-click `BriskEdit.app` → **Open** → confirm.

### Fixed

- **Format Document can no longer exhaust system memory.** Repeated formatter
  requests are now single-flight instead of launching unbounded concurrent
  tasks and retaining full buffer copies.
- Formatter shortcut key-repeat events are ignored, and stale results are
  discarded when the document changes while formatting is in progress.

### Improved

- Formatter tool and project-config discovery now runs away from the main thread,
  keeping the editor responsive during formatting.

### Compatibility

Requires macOS 26 or newer. Xcode 26+ to build from source.
