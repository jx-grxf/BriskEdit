export const DURATION = 3540; // 59s @ 60fps

/**
 * Scene starts (absolute frames). ~20-frame overlaps give crossfades.
 * Shared by BriskEditPromo.tsx (Sequences) and Sound.tsx (cue offsets).
 */
export const SCENES = {
  intro: 0,
  electron: 340,
  rescue: 850,
  demo: 1020,
  features: 2500,
  stats: 2920,
  outro: 3220,
} as const;
