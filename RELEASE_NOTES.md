# Release Notes

## 0.3.0-beta.2 — search, code intelligence & folding

A beta build. Still an unsigned developer preview — on first launch, right-click
`BriskEdit.app` → **Open** → confirm. To receive further beta updates, set the
update channel to **Beta** in Settings — the beta channel now polls its own
update feed, so in-app updates work for beta testers.

### New

- **Find in Files.** Project-wide search and replace with case / whole-word /
  regex toggles, results grouped by file. Uses ripgrep when installed (gitignore
  aware), with a pure-Swift fallback; searches dotfiles too (`.env`, `.gitignore`).
- **Code folding.** Expand/collapse blocks via chevrons in the gutter, with
  indentation-based fold regions.
- **Symbol outline.** A sidebar of the file's symbols from the language server;
  click to jump to a definition.
- **Go to Definition.** ⌘-click or F12 on a symbol.
- **Hover tooltips.** Rest the pointer on a symbol to see its type/docs from the
  language server.
- **Minimap.** A zoomed-out overview at the right edge; click or drag to scroll.
  Toggle from View ▸ Show Minimap or Settings.
- **Multi-cursor.** ⌘D selects the next occurrence as an additional cursor.
- **More languages & a language picker.** Dart, Java, Kotlin, Ruby, Lua, SQL,
  Perl, SCSS/Less, TOML, INI and more, plus a clickable language selector in the
  status bar (with auto-detect).

### Improved

- **Flicker-free highlighting.** Syntax colors are applied as TextKit 2 rendering
  attributes instead of text-storage edits, so the visible text no longer
  flashes or jumps while typing, and the whole document is colored correctly.
- **Snappier editor.** The minimap rebuilds on a debounce instead of rescanning
  the document on every keystroke; project-search numbers lines in a single pass.
- Accessibility labels for the sidebar section picker, terminal toggle, and the
  search controls.

### Compatibility

Requires macOS 26 or newer. Xcode 26+ to build from source.
