import { loadFont as loadInter } from "@remotion/google-fonts/Inter";
import { loadFont as loadMono } from "@remotion/google-fonts/JetBrainsMono";

export const inter = loadInter("normal", {
  weights: ["400", "500", "600", "700", "800"],
  subsets: ["latin"],
}).fontFamily;

export const mono = loadMono("normal", {
  weights: ["400", "500", "700"],
  subsets: ["latin"],
}).fontFamily;

// Core palette — a calm, deep macOS-dark editor with an electric accent.
export const c = {
  bg0: "#070A10", // deepest backdrop
  bg1: "#0B0F17",
  window: "#10151F", // window body
  windowEdge: "rgba(255,255,255,0.08)",
  sidebar: "#0C1018",
  editor: "#0B0F17",
  panel: "#0A0D14",
  statusbar: "#0C1018",

  text: "#E6EDF3",
  textDim: "#8B95A5",
  textFaint: "#586173",

  accent: "#5B8CFF", // electric blue
  accent2: "#56E1E0", // cyan
  warm: "#F2683A", // swift orange (Run)
  green: "#43D08A",
  pink: "#FF7B9C",

  // syntax
  synKeyword: "#FF7B8A",
  synType: "#7CC4FF",
  synString: "#9FE0A8",
  synComment: "#5C6677",
  synFunc: "#D2A8FF",
  synNumber: "#7CC4FF",
  synProp: "#56E1E0",
  synPlain: "#D6DEEA",
} as const;

export const ACCENT_GRAD = `linear-gradient(120deg, ${c.accent} 0%, ${c.accent2} 100%)`;
export const WARM_GRAD = `linear-gradient(120deg, ${c.warm} 0%, #FF9A5A 100%)`;

// Signature easing — crisp UI deceleration (no overshoot).
export const EASE_OUT = [0.16, 1, 0.3, 1] as const;
export const EASE_IN_OUT = [0.45, 0, 0.55, 1] as const;
export const EASE_POP = [0.34, 1.4, 0.64, 1] as const;
