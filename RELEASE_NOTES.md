# Release Notes

## 0.6.2 - Reliable editor rendering and a refreshed welcome screen

### Fixed

- **Visible text with the minimap enabled.** The minimap no longer paints over the editor and line numbers when editor vibrancy is off. Drawing stays inside each editor surface, including when accessibility or power settings require a solid background.
- **Reliable beta update feed.** The combined beta appcast is published under the filename that installed clients request.

### Improved

- **Refreshed welcome screen.** Recent workspaces, file and folder actions, and project context are easier to find when opening BriskEdit.
- **Clearer Nightly identity.** Nightly builds use their own app name, violet accent and window marker, with versions that indicate the release they lead to.

### Compatibility

- macOS 15 (Sequoia) or later. Liquid Glass requires macOS 26 (Tahoe).
- Release artifacts target Apple silicon.

## 0.6.1 - A new app icon and a clearer version display

### Improved

- **New app icon.** BriskEdit has a redesigned icon: code brackets with a pencil on a blue gradient. On macOS 26 it is rendered with Liquid Glass and follows the Dark, Tinted, and Clear icon styles; macOS 15 shows a matching pre-rendered icon.
- **Clearer version display.** Settings and the About BriskEdit window show the version, for example 0.6.1, instead of an internal build number such as 1006.1.99. Hover over the version in Settings to see the build number.

### Compatibility

- macOS 15 (Sequoia) or later. Liquid Glass requires macOS 26 (Tahoe).
- Builds require Xcode 26 or later. Release artifacts target Apple silicon.
