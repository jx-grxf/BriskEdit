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

export const Intro: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  const pop = spring({ frame, fps, config: { damping: 14, mass: 0.7 }, durationInFrames: 40 });
  const markScale = interpolate(pop, [0, 1], [0.6, 1]);

  const wordO = interpolate(frame, [22, 44], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const wordY = interpolate(frame, [22, 50], [26, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: Easing.bezier(...EASE_OUT),
  });
  const underline = interpolate(frame, [40, 80], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: Easing.bezier(...EASE_OUT),
  });
  const tagO = interpolate(frame, [60, 84], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const tagY = interpolate(frame, [60, 88], [16, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: Easing.bezier(...EASE_OUT),
  });

  // exit
  const out = interpolate(frame, [300, 350], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: Easing.bezier(0.45, 0, 0.55, 1),
  });
  const groupScale = 1 + out * 0.06;
  const groupO = 1 - out;

  const caretOn = Math.floor(frame / 18) % 2 === 0;

  return (
    <AbsoluteFill
      style={{ alignItems: "center", justifyContent: "center", opacity: groupO }}
    >
      <div
        style={{
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          transform: `scale(${groupScale})`,
        }}
      >
        <div style={{ transform: `scale(${markScale})`, marginBottom: 36 }}>
          <LogoMark size={160} caretOn={caretOn} />
        </div>

        <div style={{ position: "relative", opacity: wordO, transform: `translateY(${wordY}px)` }}>
          <div
            style={{
              fontFamily: inter,
              fontSize: 118,
              fontWeight: 800,
              letterSpacing: -3,
              color: c.text,
              lineHeight: 1,
            }}
          >
            Brisk<span
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
          <div
            style={{
              position: "absolute",
              left: 0,
              bottom: -14,
              height: 5,
              width: `${underline * 100}%`,
              borderRadius: 3,
              background: ACCENT_GRAD,
            }}
          />
        </div>

        <div
          style={{
            marginTop: 42,
            fontFamily: inter,
            fontSize: 30,
            fontWeight: 500,
            color: c.textDim,
            opacity: tagO,
            transform: `translateY(${tagY}px)`,
            letterSpacing: 0.3,
          }}
        >
          A native macOS code editor — built for speed, not bloat.
        </div>
      </div>
    </AbsoluteFill>
  );
};
