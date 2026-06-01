# Contributing to BriskEdit

Thanks for helping improve BriskEdit. This project is a native macOS developer tool, so changes should preserve local-first behavior, low resource use, and a small trusted surface area.

## Good First Contributions

- Syntax-highlighting rules for additional languages (Tree-sitter grammars).
- Run-button toolchain entries for languages not yet supported.
- Accessibility, keyboard, and VoiceOver polish.
- Unit tests for `TextDocument`, `WorkspaceModel`, and `RunService` resolution.
- Documentation fixes that make installation or preview status clearer.

## Development Setup

```bash
brew install xcodegen
xcodegen
xcodebuild -project BriskEdit.xcodeproj -scheme BriskEdit -configuration Debug build
./script/build_and_run.sh
```

Requires macOS 26 or newer with Xcode 26+. The `project.yml` is the source of truth; the generated `.xcodeproj` is ignored. Regenerate after touching `project.yml`.

## Pull Request Guidelines

- Keep PRs focused on one behavior or documentation area.
- Explain the user-facing impact and the validation you ran.
- Add or update tests when changing document, workspace, or run-resolution behavior.
- No telemetry, network upload, account requirement, or backend dependency without a dedicated design discussion first.
- No third-party SwiftPM dependency added without a one-line justification of what it replaces (a hand-written 50-line file is almost always better than a new package).
- Match the existing code style: `@Observable` over `ObservableObject`, `@MainActor` on UI types, no `Combine` in the editor pipeline.

## Release Changes

Release-facing changes should update `RELEASE_NOTES.md` or `docs/release.md` when they affect download, packaging, signing, installer behavior, or public trust.

