# BriskEdit promo video

The source for the 60-second product video shown in the main README. Built with
[Remotion](https://www.remotion.dev) — the whole thing is React: every frame is
a render of the composition at a given frame number, screenshotted by headless
Chrome and encoded to MP4 with FFmpeg.

## Run it

```bash
cd promo
npm install
npx remotion studio        # live preview with a frame scrubber
```

## Render

```bash
npx remotion render BriskEditPromo out/BriskEdit-Promo.mp4 \
  --codec=h264 --crf=16 --jpeg-quality=100 --concurrency=4
```

Output: 1920×1080, 60 fps, ~59 s. `out/` is gitignored.

## Structure

- `src/Root.tsx` — composition registration (1920×1080, 60 fps).
- `src/timeline.ts` — `DURATION` and the absolute start frame of each scene.
- `src/BriskEditPromo.tsx` — composes the seven scenes as `Sequence`s.
- `src/scenes/` — the acts, in order:
  1. `Intro` — logo + wordmark brand open
  2. `ElectronPain` — the Electron status quo (ballooning RAM, crash toasts)
  3. `RescueBridge` — the turn
  4. `Demo` — the editor in action (typing, completion, diagnostics, Run, terminal)
  5. `FeatureGrid` — breadth, eight feature cards
  6. `Stats` — the no-bloat numbers
  7. `Outro` — CTA
- `src/components/` — `Window` (the faux editor window), `CodeView`,
  `Background`, `Logo`, and `Sound` (every audio cue, keyed to absolute frames).
- `public/sfx/` — the sound effects. `public/appicon.png` is the real app icon.

## Notes

- Animation is **frame-driven only** (`useCurrentFrame()` + `interpolate()` +
  `spring()`). No CSS transitions/animations — they don't render deterministically.
- The typing sound rotates eight real mechanical-keystroke samples
  (`public/sfx/key1…key8`); cascades use a single `ping` with a rising
  `playbackRate` per item.
