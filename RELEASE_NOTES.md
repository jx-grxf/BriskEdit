# Release Notes

## 0.5.1 - Source control history, Java, Markdown, and stability fixes

BriskEdit 0.5.1 builds on 0.5.0 with a richer Source Control pane, Java support,
a much nicer Markdown preview, and an important editor undo crash fix. It
remains an unsigned developer preview; on first launch, right-click
`BriskEdit.app`, choose **Open**, and confirm.

### Added

- **Commit history in Source Control.** The sidebar now lists recent commits with
  a graph lane, marks the commits you haven't pushed yet, and lets you copy a
  commit's SHA or message.
- **Run and IntelliSense for Java.** Run Java files straight from the editor and
  get completion, diagnostics and hovers when a Java language server is installed.

### Improved

- **Source Control keeps itself up to date.** Opening the pane, returning to the
  window, or saving a file now refreshes the status and change list immediately —
  no manual refresh needed.
- **Richer Markdown preview.** Ordered lists, task-list checkboxes, horizontal
  rules, more heading levels, italics and strikethrough, all with a cleaner,
  GitHub-style look that adapts to light and dark.

### Fixed

- **No more crash after a folder drop.** Dropping a folder to swap the workspace
  root no longer leaves stale editor undo registrations that could crash on the
  next ⌘Z.

### Compatibility

- macOS 26 (Tahoe) or later, Apple silicon.
