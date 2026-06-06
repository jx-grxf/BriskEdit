# Release Notes

## 0.3.2 — Editor fixes, Format Document & Discord presence

A focused fix release on top of 0.3.1. Still an unsigned developer preview — on
first launch, right-click `BriskEdit.app` → **Open** → confirm.

### Added

- **Format Document** for supported languages, right from the editor: right-click
  → *Format Document* or press ⇧⌥F. It honours a project `.clang-format` (and
  falls back to your editor indent width), and a format is a single ⌘Z undo.
- **Discord Rich Presence** (experimental, opt-in under Settings → Experimental):
  show the file, language and workspace you're working on, with per-field privacy
  toggles. Off by default.
- BriskEdit now registers as an editor for common code files, so they can open
  in it directly from Finder.

### Fixed

- **Code folding no longer glitches.** Folding a block — or typing while a fold
  was active — could leave black lines and a jumping viewport. Folding now
  relayouts surgically and repaints cleanly.
- **Dropping a file into an empty folder** in the file tree now shows it
  immediately instead of leaving it invisible until a second drop.

### Improved

- File-tree drag & drop: animated drop-target highlight, spring-loaded folder
  auto-expand on hover, and a clearer drag preview.

### Compatibility

Requires macOS 26 or newer. Xcode 26+ to build from source.
