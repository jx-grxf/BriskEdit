# BriskEdit Full Product Audit - 2026-06-02

Scope: read-only frontend, backend/service, and feature audits after finishing
`feat/syntax-themes-visual-polish` at `da33e62`.

## Current Release State

- Live stable: `0.2.0`, Sparkle build `4`, appcast asset from `v0.2.0`.
- Live beta: `0.3.0-beta.2`, Sparkle build `6`, beta appcast asset from
  `v0.3.0-beta.2`.
- Finished but unreleased: `feat/syntax-themes-visual-polish` (`da33e62`),
  pushed to GitHub and intended for `0.3.0-beta.3`.
- Open PRs at audit time: none.
- Remaining merged cleanup branches: `feat/code-folding` and
  `feat/search-multicursor-lsp-nav` are already merged into `main` but still
  exist locally/remotely.

## What Ships Where

### Stable `0.2.0`

Stable currently contains the terminal/update hardening release:

- Multi-session terminal with configurable terminal font.
- Terminal usable without an open file.
- Automatic update checks and toolbar update affordance.
- File-finder and terminal interaction hardening.
- Sparkle release rebuild support and release identity checks.

### Beta `0.3.0-beta.2`

Beta currently adds the editor feature wave:

- Find in Files.
- Code folding.
- Symbol outline.
- Go to Definition.
- Hover tooltips.
- Minimap.
- Multi-cursor via Cmd-D.
- More languages and a status-bar language picker.
- Flicker-free rendering-attribute syntax highlighting.
- Beta feed polling fix.

### Next Beta Candidate `0.3.0-beta.3`

The completed theme branch should ship as the next beta candidate:

- Built-in color themes.
- VS Code `.json` / JSONC theme import.
- Imported theme persistence and deletion.
- Appearance settings with theme preview.
- View menu font-size controls.
- Git gutter visibility preference.
- Release workflow step to refresh `johannesgrof.me` after publishing.

This branch is beta-ready after tests, but it should not be promoted directly to
stable without the fixes below.

## Release Recommendation

1. Cut `0.3.0-beta.3` from `feat/syntax-themes-visual-polish` after opening and
   merging a PR.
2. Use `0.3.x` beta releases to fix the P1/P2 issues in this audit.
3. Promote to stable only after the save/autosave race, LSP lifecycle/rooting,
   language-change diagnostics, search limits, Markdown preview jank, and
   signing/notarization policy are handled.

Stable is not yet a polished public stable. The app still defaults to ad-hoc
preview signing in `project.yml`, and notarization is optional in the release
script. A true public stable should require Developer ID signing, notarization,
stapling, and Gatekeeper verification.

## P1 - Fix Before Stable

### Save/autosave can mark newer edits clean

`TextDocument.save()` writes a snapshot off the main actor and then clears
`isDirty` unconditionally. If the user types while a slow save or autosave is in
flight, a newer unsaved revision can be marked clean.

Plan:

- Capture the document revision with each save snapshot.
- Track `lastSavedRevision`.
- Clear `isDirty` only if the current revision still matches the saved
  revision.
- Add a delayed-write test: edit A, start save, edit B before completion, verify
  dirty state remains true.

### LSP startup and request lifecycle are fragile

`LSPService` currently caches one server per language/config ID, starts servers
before a robust cleanup path exists, and sends requests before registering the
pending continuation. A failed initialize can leave a process running and keep
the language disabled until app restart.

Plan:

- Register pending request continuations before writing the JSON-RPC frame.
- Make request timeouts cancellable and remove continuations exactly once.
- On failed start, terminate/unregister the process and remove the cached server.
- Key servers by `(serverID, rootURI)`, not only language.
- Build root URIs with `URL(fileURLWithPath: root).absoluteString`.
- Add fake LSP tests for immediate responses, initialize timeout cleanup, and two
  separate roots for the same language.

### LSP project root is wrong

Editor completion, hover, definition, warmup, and outline use the file's parent
folder as root. That breaks SwiftPM, clangd compile databases, TypeScript, Go,
Rust, and multi-root windows.

Plan:

- Pass `workspace.rootURL` into `TextKit2EditorHost`.
- Use workspace root for LSP initialize when available.
- Fall back to the file parent only for single-file editing.
- Add tests or a fake server fixture that asserts initialize root selection.

### Language changes do not reset diagnostics or LSP state

Changing language in the picker re-highlights, but does not close the old LSP
document, clear diagnostics, register a new diagnostics handler, or warm up the
new language server.

Plan:

- Detect URI and language changes in the editor coordinator.
- Remove the old diagnostics handler and send `didClose`.
- Clear stale diagnostics when switching to unsupported languages.
- Warm up the new LSP when switching to a supported language.
- Make `checkActiveDocument()` clear diagnostics when no checker is available.

### Markdown preview reloads too aggressively

Markdown preview rebuilds and reloads full HTML directly from `document.text`.
Typing can flicker, reset scroll, and feel laggy.

Plan:

- Debounce render/load.
- Preserve preview scroll position across updates.
- Move expensive Markdown conversion off the main actor if it grows.
- Add a typing smoke/perf test or manual verification scenario.

## P2 - Next Beta Hardening

### Dirty Run/Check can use stale project files

Dirty saved files and untitled buffers are staged into `/tmp` for some checks,
while SwiftPM uses `swift run` from the package root and therefore ignores the
unsaved buffer. C/C++ includes can also break when temporary files leave the
source directory.

Plan:

- Prompt "Save before Run" for file-backed dirty project runs.
- For C/C++, prefer sibling temp files or pass include paths from the real file.
- For SwiftPM, require save before package run or introduce a clear overlay
  strategy.
- Add tests for dirty SwiftPM and dirty C-with-local-header behavior.

### Find in Files needs bounded streaming and error feedback

The ripgrep path reads all JSON output before applying `matchLimit`, and invalid
regex or ripgrep errors look like empty results.

Plan:

- Stream ripgrep JSON lines.
- Terminate the process once the global match limit is reached.
- Add `--max-filesize` or equivalent filtering.
- Surface invalid regex and process errors in the search UI.
- Add tests for invalid regex and high-match-count repositories.

### MainActor file operations can block the UI

Create, copy, move, trash, import, and dirty temporary source writes run
synchronously from main-actor code.

Plan:

- Move disk operations into detached tasks.
- Return UI state updates to the main actor.
- Add manual verification with a large folder import/move while typing.

### Save As / rename needs watcher and diagnostics retargeting

Save As does not restart file watching. Rename restarts watchers, but editor LSP
diagnostics are registered only during initial warmup.

Plan:

- Restart watchers after Save As.
- Retarget diagnostics and LSP URI on Save As and rename.
- Verify untitled-to-Swift Save As receives file watching and diagnostics.

### Beta feed semantics are misleading

The code says beta accepts stable and beta channels, but the beta channel polls a
moving beta-only feed that contains only the latest beta appcast item.

Plan:

- Decide product semantics:
  - beta-only feed, documented clearly; or
  - combined feed containing latest beta and latest stable.
- Add appcast validation for stable/beta channel behavior.

### UI control semantics and layout polish

Several interactive rows are gesture-only or icon-only, and split/status surfaces
can get cramped.

Plan:

- Replace tab, terminal, and git row `onTapGesture` paths with real controls
  where practical.
- Add accessibility labels/values to icon-only actions.
- Use priority or popovers in the status bar so cursor/diagnostics stay visible.
- Make Markdown preview resizable/collapsible or auto-hide below a width
  threshold.

## Stable Backlog

- Incremental or visible-range syntax highlighting, not full-document passes for
  medium/large files.
- Cached line index for LSP positions and navigation.
- Git gutter large-file limits, HEAD blob caching, and idle-only diffing.
- More robust folding anchors or providers for brace/marker-based languages.
- Broader QuickLook preview support with "Open as Text".
- Better Markdown rendering for links, fenced code, lists, images, and tables.
- Better language detection for shebangs and extensions such as `.m`, `.mm`,
  `.vue`, and `.svelte`.
- Public stable release gate: Developer ID signing, notarization, stapling,
  `spctl` verification, and a documented rollback path.

## Suggested Implementation Order

Status in PR #8:

- Done: save/autosave revision correctness.
- Done: LSP lifecycle/rooting and language-change diagnostics retargeting.
- Done: bounded search with ripgrep streaming, max filesize, invalid-regex and
  process-error feedback.
- Done: debounced Markdown preview with scroll preservation and broader block
  rendering.
- Done: save-before-run behavior for dirty project runs and sibling temp files
  for C/C++ local headers.
- Done: detached workspace file operations for create, folder create, duplicate,
  import, move, rename, and trash paths.
- Done: tab, terminal, and git rows use explicit controls with accessibility
  labels where practical; narrow Markdown preview auto-hides.
- Done: beta feed semantics are beta-only and stable release gates require
  Developer ID signing, notarization, stapling, and Gatekeeper checks.

1. `fix/save-revision-race`: save/autosave revision correctness and tests.
2. `fix/lsp-lifecycle-rooting`: LSP root keys, request ordering, failed-start
   cleanup, diagnostics retargeting.
3. `fix/language-change-diagnostics`: language picker clears/rewires diagnostics
   and check results.
4. `fix/search-streaming-errors`: bounded ripgrep streaming and invalid-regex UI.
5. `fix/markdown-preview-debounce`: debounce preview and preserve scroll.
6. `fix/run-dirty-project-files`: save-before-run behavior and temp-file policy.
7. `fix/mainactor-file-ops`: detach workspace file operations.
8. `ui/accessibility-layout-polish`: real controls, labels, status bar, responsive
   preview.
9. `release/stable-gates`: signing/notarization required for stable promotion.

## Verification Bundle

Run before each beta candidate:

```bash
xcodegen
xcodebuild test -project BriskEdit.xcodeproj -scheme BriskEdit -destination 'platform=macOS'
./script/build_and_run.sh build-only
./script/audit_release_identity.sh
```

Manual smoke tests before stable:

- Type continuously in 100k and 500k character files.
- Open Markdown preview and type while preserving preview scroll.
- Switch language from C/Swift to Plain Text and back; diagnostics must clear and
  return correctly.
- Save As an untitled supported-language file and verify file watching,
  diagnostics, and session restore.
- Run dirty SwiftPM and dirty C-with-local-header files.
- Search a large repo with invalid regex and more than 5000 matches.
- Check stable and beta Sparkle appcasts from older builds.
- Verify signed/notarized release with `codesign`, `spctl`, and stapler.
