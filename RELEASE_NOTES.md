# Release Notes

## 0.3.1 — UI polish & a product demo

A small, stable follow-up to 0.3.0. Still an unsigned developer preview — on
first launch, right-click `BriskEdit.app` → **Open** → confirm.

### Improved

- Refreshed editor chrome: a native front-tab look, a calmer Run button,
  consistent design tokens, and a clearer status-bar type ramp.
- Settings now use translucent forms, gained a dedicated editor font picker,
  and show a last-update-check date that refreshes live after an update cycle.
- The whole tab chip is clickable, and the sidebar cross-fades between views.

### Docs

- Added a 30-second product demo video to the README.

### Internal

- Hardened the release pipeline: releases are serialized and the release notes
  are verified before a build starts.

### Compatibility

Requires macOS 26 or newer. Xcode 26+ to build from source.
