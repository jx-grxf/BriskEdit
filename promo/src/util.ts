import { Easing, interpolate } from "remotion";

type Curve = readonly [number, number, number, number];

/** Eased 0→1 ramp over [start, start+dur]. */
export const ramp = (
  frame: number,
  start: number,
  dur: number,
  curve: Curve = [0.16, 1, 0.3, 1],
) =>
  interpolate(frame, [start, start + dur], [0, 1], {
    easing: Easing.bezier(curve[0], curve[1], curve[2], curve[3]),
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

/** Fade in then out: 0→1 over `inDur`, hold, 1→0 over `outDur` before `end`. */
export const fadeInOut = (
  frame: number,
  start: number,
  end: number,
  inDur = 14,
  outDur = 14,
) => {
  const a = ramp(frame, start, inDur);
  const b = interpolate(frame, [end - outDur, end], [1, 0], {
    easing: Easing.bezier(0.45, 0, 0.55, 1),
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  return Math.min(a, b);
};

export const mix = (a: number, b: number, t: number) => a + (b - a) * t;
