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

const Badge: React.FC<{ text: string }> = ({ text }) => (
  <div
    style={{
      padding: "11px 20px",
      borderRadius: 12,
      background: "rgba(255,255,255,0.05)",
      border: "1px solid rgba(255,255,255,0.1)",
      fontFamily: inter,
      fontSize: 18,
      fontWeight: 600,
      color: c.textDim,
    }}
  >
    {text}
  </div>
);

export const Outro: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  const pop = spring({ frame, fps, config: { damping: 13, mass: 0.7 }, durationInFrames: 42 });
  const markScale = interpolate(pop, [0, 1], [0.5, 1]);

  const wordO = interpolate(frame, [16, 38], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  const wordY = interpolate(frame, [16, 44], [22, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: Easing.bezier(...EASE_OUT),
  });

  const ctaPop = spring({ frame: frame - 44, fps, config: { damping: 12, mass: 0.6 }, durationInFrames: 36 });
  const ctaScale = interpolate(ctaPop, [0, 1], [0.85, 1]);

  const badgesO = interpolate(frame, [70, 92], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  const urlO = interpolate(frame, [86, 108], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });

  // gentle continuous glow pulse on CTA
  const pulse = 0.5 + 0.5 * Math.sin((frame - 44) / 14);
  const glow = 0.35 + pulse * 0.35;

  return (
    <AbsoluteFill style={{ alignItems: "center", justifyContent: "center" }}>
      <div style={{ display: "flex", flexDirection: "column", alignItems: "center" }}>
        <div style={{ transform: `scale(${markScale})`, marginBottom: 30 }}>
          <LogoMark size={120} caretOn={Math.floor(frame / 18) % 2 === 0} />
        </div>

        <div
          style={{
            fontFamily: inter,
            fontSize: 86,
            fontWeight: 800,
            letterSpacing: -2.5,
            color: c.text,
            opacity: wordO,
            transform: `translateY(${wordY}px)`,
            lineHeight: 1,
          }}
        >
          Brisk
          <span
            style={{
              background: ACCENT_GRAD,
              WebkitBackgroundClip: "text",
              WebkitTextFillColor: "transparent",
              backgroundClip: "text",
            }}
          >
            Edit
          </span>
        </div>

        {/* CTA */}
        <div
          style={{
            marginTop: 44,
            transform: `scale(${ctaScale})`,
            opacity: Math.min(ctaPop * 2, 1),
          }}
        >
          <div
            style={{
              display: "flex",
              alignItems: "center",
              gap: 12,
              padding: "18px 38px",
              borderRadius: 16,
              background: ACCENT_GRAD,
              fontFamily: inter,
              fontSize: 26,
              fontWeight: 700,
              color: "#06121f",
              boxShadow: `0 20px 60px -10px rgba(91,140,255,${glow})`,
            }}
          >
            <span style={{ fontSize: 22 }}>↓</span> Download free on GitHub
          </div>
        </div>

        <div
          style={{
            marginTop: 30,
            display: "flex",
            gap: 14,
            opacity: badgesO,
          }}
        >
          <Badge text="macOS 26+" />
          <Badge text="Swift 6" />
          <Badge text="Open source · MIT" />
        </div>

        <div
          style={{
            marginTop: 30,
            fontFamily: inter,
            fontSize: 22,
            fontWeight: 500,
            color: c.textFaint,
            opacity: urlO,
            letterSpacing: 0.5,
          }}
        >
          github.com/jx-grxf/BriskEdit
        </div>
      </div>
    </AbsoluteFill>
  );
};
