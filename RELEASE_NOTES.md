# Release Notes

## 0.3.0 — themes, search, code intelligence & polish

The first stable 0.3.0 build. Still an unsigned developer preview — on first
launch, right-click `BriskEdit.app` → **Open** → confirm.

### New

- **Color themes.** Built-in palettes including System (VS Code), One Dark,
  Dracula, Nord, Solarized Dark, Monokai, and GitHub Light, switchable from the
  View menu.
- **VS Code theme import.** Import `.json` color themes, preview them in
  Settings, persist them, and remove them again when no longer needed.
- **Find in Files.** Project-wide search and replace with case / whole-word /
  regular-expression options.
- **Markdown preview.** Live split-screen preview with working in-page and
  relative links; toggle it from the View menu or close it inline.
- **Image viewing.** Open PNG, JPEG, GIF, and other common image formats,
  inline or in a split preview.
- **Open Recent.** The File menu lists recently opened folders for quick reopen.
- **Terminal font picker.** Choose any installed monospaced font for the
  integrated terminal from Settings.
- **Tool Health.** Inspect and install missing language tools with live install
  progress.
- **Appearance & font-size commands.** Editor font, minimap, and git gutter
  bars live in a dedicated Appearance tab; increase/decrease/reset font size
  from the View menu.

### Improved

- Code folding collapses a block to a single clean header line and keeps gutter
  line numbers consistent.
- Windows open at the full visible size, and a cold start restores exactly one
  window.
- Running C and C++ files resolves system headers through the installed SDK.
- Folding controls only appear for languages where folding makes sense.

### Compatibility

Requires macOS 26 or newer. Xcode 26+ to build from source.
