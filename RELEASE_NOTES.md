# Release Notes

## 0.5.0 - Movable tabs, smarter setup, optional source control

BriskEdit 0.5.0 makes the window your own and smooths first-run setup. It remains
an unsigned developer preview; on first launch, right-click `BriskEdit.app`,
choose **Open**, and confirm.

### Added

- **Drag tabs anywhere.** Reorder tabs within the strip, tear one off onto the
  desktop to open it in a new window, or drop it on another window to move it
  there — keeping unsaved edits and the language server intact. Dropping onto a
  specific tab inserts it at that position.
- **Keyboard and overflow tab controls.** Move the active tab with `⌃⌘←` / `⌃⌘→`
  (also in the File menu), and jump to any open tab from the overflow menu that
  appears when the strip is full.
- **Onboarding that sets up your tools.** The first-run flow now detects the
  compilers, language servers, and formatters already on your Mac and offers to
  install the missing ones — Xcode Command Line Tools, Homebrew packages, and
  more — with one click. It also previews your theme live, installs the optional
  command-line launcher, and can open your first folder.
- **An About page** in Settings with the version, license, and project links.

### Improved

- **Smoother tab reordering.** Tabs glide into place with a spring and a clear
  drop indicator.
- **Optional source control.** A single switch turns the Source Control sidebar,
  gutter change bars, and inline blame on or off — for when you're not working in
  a repository. Available in onboarding and Settings.
- **Tidier Settings and welcome screen.** All preference tabs fit on one row
  without an overflow menu, and the welcome header shows the author and version.

### Fixed

- The Recent folders list no longer keeps temporary or deleted directories.

### Compatibility

- macOS 26 (Tahoe) or later, Apple silicon.
