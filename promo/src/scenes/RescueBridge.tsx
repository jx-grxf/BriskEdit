import {
  AbsoluteFill,
  Easing,
  interpolate,
  spring,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import { c, inter, ACCENT_GRAD, EASE_OUT } from "../theme";
import { LogoMark } from "../components/Logo";

/**
 * The turn: after the Electron mess gets yanked away, this short beat flips the
 * script before the product demo. Mostly typographic so it doesn't feel like a
 * second title card.
 */
export const RescueBridge: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  const markPop = spring({ frame, fps, config: { damping: 14, mass: 0.6 }, durationInFrames: 30 });
  const markScale = interpolate(markPop, [0, 1], [0.5, 1]);

  const lineO = interpolate(frame, [16, 40], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  const lineY = interpolate(frame, [16, 46], [24, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: Easing.bezier(...EASE_OUT),
  });

  const subO = interpolate(frame, [44, 66], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });

  // exit zoom into the demo
  const out = interpolate(frame, [150, 190], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: Easing.bezier(0.45, 0, 0.55, 1),
  });

  return (
    <AbsoluteFill
      style={{
        alignItems: "center",
        justifyContent: "center",
        opacity: 1 - out,
        transform: `scale(${1 + out * 0.06})`,
      }}
    >
      <div style={{ display: "flex", flexDirection: "column", alignItems: "center" }}>
        <div style={{ transform: `scale(${markScale})`, marginBottom: 30 }}>
          <LogoMark size={92} caretOn={Math.floor(frame / 18) % 2 === 0} />
        </div>
        <div
          style={{
            fontFamily: inter,
            fontSize: 72,
            fontWeight: 800,
            letterSpacing: -2,
            color: c.text,
            opacity: lineO,
            transform: `translateY(${lineY}px)`,
            textAlign: "center",
            lineHeight: 1.05,
          }}
        >
          There's a{" "}
          <span
            style={{
              background: ACCENT_GRAD,
              WebkitBackgroundClip: "text",
              WebkitTextFillColor: "transparent",
              backgroundClip: "text",
            }}
          >
            faster
          </span>{" "}
          way.
        </div>
        <div
          style={{
            marginTop: 24,
            fontFamily: inter,
            fontSize: 26,
            fontWeight: 500,
            color: c.textDim,
            opacity: subO,
            letterSpacing: 0.3,
          }}
        >
          Same Mac. None of the weight.
        </div>
      </div>
    </AbsoluteFill>
  );
};
