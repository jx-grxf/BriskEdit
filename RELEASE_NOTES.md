# Release Notes

## 0.1.0 — unreleased preview

First public scaffold. Not yet a usable editor for daily work.

### What works

- App shell, single-window workspace with `NavigationSplitView`.
- Open file / open folder, recent tabs, basic file tree sidebar.
- `NSTextView` editor with TextKit 2 backing and a custom line-number gutter.
- Tab-to-spaces, configurable tab width, font size in Settings.
- Find bar (`⌘F`) via the standard AppKit find UI.
- Command Palette (`⇧⌘P`).
- Save / Save As… with encoding round-trip.
- Sparkle update channel selector (stable / beta), wiring in place, no published feed yet.

### Known gaps

- No syntax highlighting yet (Tree-sitter lands in MVP-1).
- No integrated terminal yet (SwiftTerm lands in MVP-1).
- No Markdown preview yet (lands in MVP-1).
- No Run button yet (lands in MVP-1).
- No external file-change reload (FSEvents lands in MVP-1).
- Find-in-folder is in-file only.
- Multi-cursor and column selection are not implemented.

### Compatibility

Requires macOS 26 or newer. Xcode 26+ to build from source.

### Verification before tagging

- `xcodegen && xcodebuild -scheme BriskEdit -configuration Release build` succeeds.
- `codesign --verify --deep --strict` on the resulting `.app` returns clean.
- DMG mounts and the app launches from `/Applications` after the drag.
