# Release Notes

## 0.5.2 - Signed and notarized builds, smarter editing, stability fixes

BriskEdit 0.5.2 is the first release that is signed with a Developer ID and
notarized by Apple. The DMG now opens like any other Mac app — no more
right-click-and-Open dance. Existing installs update seamlessly through the
built-in updater; because the signing identity changed, macOS may ask once to
re-confirm previously granted permissions.

### Added

- **Signed and notarized releases.** Every build is now signed with a Developer
  ID certificate, hardened, and notarized by Apple, so Gatekeeper accepts it
  out of the box.
- **Surround selection with brackets or quotes.** Select text and type `(`,
  `[`, `{`, `"` or `'` to wrap it instead of replacing it, with the selection
  kept so you can keep typing.

### Improved

- **Smarter bracket and quote pairing.** Typing a closer that's already next to
  the caret steps over it instead of doubling it, backspace inside an empty
  pair removes both characters, and quotes no longer auto-close next to a word
  (so `don't` stays `don't`).
- **Closing many tabs respects Cancel.** "Close All" and "Close Other Tabs" now
  prompt for each unsaved file in order and stop the moment you cancel, leaving
  the remaining tabs open.
- **Faster syntax highlighting.** Large files re-highlight with noticeably less
  overhead while typing.
- **Sharper file-tree filtering.** `bin` and `obj` folders are only hidden when
  they are actually .NET build output — hand-written `bin/` folders in Go,
  Rails, or Node projects stay visible.

### Fixed

- **Rapid saves can no longer lose an edit.** A save landing while an autosave
  was still writing could previously leave the older content on disk; writes
  are now strictly ordered.
- **Huge growing files no longer bog down the app.** A watched file that grows
  past the editing size limit (for example a busy log) is no longer re-read
  into memory on every change.
- **Find in Files can't hang anymore.** A search tool stuck on an unresponsive
  network folder is now force-quit instead of freezing the search forever.

### Compatibility

- macOS 26 (Tahoe) or later, Apple silicon.
