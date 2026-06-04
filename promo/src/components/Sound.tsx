import { Audio, Sequence, staticFile } from "remotion";
import { SCENES } from "../timeline";

/**
 * Sound design layer. Cues are authored per scene in LOCAL frames, then offset
 * by the scene's start (SCENES) so audio stays glued to the visuals.
 *
 * Palette (public/sfx):
 *   key1…key8 — real mechanical keystrokes; one per character while the code
 *               types itself (rotated for non-repetitive, realistic typing)
 *   popup   — LSP completion popup appears
 *   error   — diagnostic / warning squiggle
 *   crash   — Electron crash toasts
 *   ping    — cascades (lang chips, feature cards, stat numbers); pitch rises
 *             per item via playbackRate so the cascade "builds up"
 *   run     — Run button press
 *   whoosh  — scene / element entrances, terminal rising
 *   whip    — logo pops
 *   ding    — build "ready" confirm + final CTA
 *   fah     — the sad-trombone when the Electron window chokes
 */

type Cue = { file: string; at: number; volume: number; rate?: number };

const Cue: React.FC<Cue> = ({ file, at, volume, rate }) => (
  <Sequence from={Math.round(at)} name={`sfx:${file}@${Math.round(at)}`}>
    <Audio src={staticFile(`sfx/${file}.wav`)} volume={volume} playbackRate={rate ?? 1} />
  </Sequence>
);

const offset = (base: number, cues: Cue[]): Cue[] =>
  cues.map((c) => ({ ...c, at: c.at + base }));

// Dense keystroke bed across [start,end] (local frames), ~7-8 keys/sec,
// rotating the 8 samples with slight timing + volume jitter so it reads as a
// human typing, not a metronome.
const typing = (start: number, end: number, step = 8): Cue[] => {
  const cues: Cue[] = [];
  let i = 0;
  for (let f = start; f <= end; f += step) {
    const jitter = ((i * 37) % 5) - 2; // -2..+2 frames
    cues.push({
      file: `key${(i % 8) + 1}`,
      at: f + jitter,
      volume: 0.17 + ((i * 13) % 5) * 0.012,
      rate: 0.97 + ((i * 7) % 6) * 0.011, // subtle pitch variation
    });
    i++;
  }
  return cues;
};

// Cascade of pings with rising pitch.
const cascade = (frames: number[], vol = 0.16): Cue[] =>
  frames.map((at, i) => ({ file: "ping", at, volume: vol, rate: 1.0 + i * 0.05 }));

const CUES: Cue[] = [
  // 1 · Intro
  ...offset(SCENES.intro, [
    { file: "whip", at: 4, volume: 0.42 },
  ]),

  // 2 · Electron
  ...offset(SCENES.electron, [
    { file: "whoosh", at: 6, volume: 0.2 }, // window appears
    { file: "fah", at: 30, volume: 0.62 }, // …and chokes
    { file: "crash", at: 62, volume: 0.28 }, // crash toast 1
    { file: "crash", at: 152, volume: 0.26 }, // crash toast 2
    { file: "crash", at: 302, volume: 0.26 }, // crash toast 3
    { file: "whoosh", at: 480, volume: 0.5 }, // yanked away
  ]),

  // 3 · Rescue bridge
  ...offset(SCENES.rescue, [
    { file: "whoosh", at: 2, volume: 0.4 },
    { file: "whip", at: 18, volume: 0.34 },
  ]),

  // 4 · Demo
  ...offset(SCENES.demo, [
    { file: "whoosh", at: 4, volume: 0.5 }, // window slides up
    ...typing(40, 372, 8), // real keystrokes, faster cadence
    { file: "popup", at: 382, volume: 0.5 }, // completion popup
    { file: "error", at: 602, volume: 0.4 }, // diagnostic squiggle
    { file: "run", at: 858, volume: 0.55 }, // Run button press
    { file: "whoosh", at: 905, volume: 0.4 }, // terminal rises
    { file: "ding", at: 1180, volume: 0.42 }, // "ready in 0.011 s"
    ...cascade([0, 1, 2, 3, 4, 5].map((i) => 1205 + i * 9)), // lang chips
  ]),

  // 5 · Feature grid
  ...offset(SCENES.features, [
    { file: "whoosh", at: 2, volume: 0.35 },
    ...cascade([0, 1, 2, 3, 4, 5, 6, 7].map((i) => 32 + i * 11), 0.13),
  ]),

  // 6 · Stats
  ...offset(SCENES.stats, [
    { file: "whoosh", at: 2, volume: 0.38 },
    ...cascade([0, 1, 2, 3].map((i) => 46 + i * 16), 0.22),
  ]),

  // 7 · Outro
  ...offset(SCENES.outro, [
    { file: "whoosh", at: 2, volume: 0.5 }, // logo
    { file: "ding", at: 54, volume: 0.5 }, // CTA confirm
  ]),
];

export const Sound: React.FC = () => (
  <>
    {CUES.map((cue, i) => (
      <Cue key={i} {...cue} />
    ))}
  </>
);
