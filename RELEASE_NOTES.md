# Release Notes

## 0.6.0 - Safer editing, draft recovery, and native review tools

### Added

- **Recover unsaved drafts.** Local recovery copies include untitled files and restore as new copies. Recovery keeps up to 20 drafts, 2 MiB each and 20 MiB total, for up to 14 days; configure it in General settings.
- **Compare with Disk.** Inspect a read-only diff before reloading or overwriting a file changed by another app.
- **Find References.** Ask the installed language server for symbol references and open each result at its exact location. Unsupported servers report a clear explanation.
- **Git diff review.** View staged HEAD-to-index and unstaged index-to-working-tree changes from Source Control.
- **Keyboard tab navigation.** Shift–Command–[ and ] select the previous and next tab without reordering them. Reopen Closed Tab and recent-file navigation are also available.

### Improved

- **Native materials and broader compatibility.** Supports macOS 15 and later, with Liquid Glass surfaces on macOS 26, material fallbacks on older systems, and accessibility-aware effects.
- **Faster folding.** Linear region analysis replaces repeated scans and runs off the main thread; stale results are discarded.
- **Responsive background work.** Cancelled searches stop their processes, session restore bounds concurrent file loads, and Tool Health probes run with limited parallelism.
- **Accessible panels and stable windows.** Resize handles support keyboard and assistive actions; early manual window resizing is no longer undone.

### Fixed

- **Reliable tab closing.** Close buttons no longer share selection or drag gestures. Re-rendering tabs cannot start phantom drags, and late callbacks cannot reactivate a closed tab.
- **External edits are protected from autosave.** Conflicts require a deliberate overwrite or reload decision.
- **Trash and rename preserve unsaved work.** Dirty tabs are resolved before deletion, and file moves wait for pending writes. Divergent edits in multiple windows can be saved as separate copies.
- **Reliable process deadlines.** Detached descendants holding pipes and blocked stdin no longer keep tool calls waiting indefinitely.
- **Language-server lifetime across windows.** Closing one tab no longer closes a document still owned by another window; cancelling Quit keeps the servers running.
- **Persistent file watching.** External-change detection recovers after longer delete/recreate gaps.
- **Ordered Git operations.** Mutations in the same workspace are serialized to prevent concurrent index writes.
- **Safer local builds.** Build-only leaves the running editor alone; relaunch uses the normal unsaved-changes dialog.
- **Stable and beta update feeds.** Beta users can receive the latest beta or stable release, generated feeds retain both channels, and release verification checks archive signatures and version identity.

### Compatibility

- macOS 15 (Sequoia) or later. Liquid Glass requires macOS 26 (Tahoe).
- Builds require Xcode 26 or later. Release artifacts target Apple silicon.


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
