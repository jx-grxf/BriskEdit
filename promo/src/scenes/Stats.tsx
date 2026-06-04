import { AbsoluteFill, Easing, interpolate, useCurrentFrame } from "remotion";
import { c, inter, ACCENT_GRAD, EASE_OUT } from "../theme";
import { ramp } from "../util";

type Stat = {
  value: number;
  prefix?: string;
  suffix?: string;
  decimals?: number;
  label: string;
  gradient?: boolean;
};

const STATS: Stat[] = [
  { value: 120, prefix: "< ", suffix: " MB", label: "Idle memory footprint", gradient: true },
  { value: 0, label: "Telemetry · accounts · cloud" },
  { value: 7, suffix: "+", label: "Languages, one Run button", gradient: true },
  { value: 100, suffix: "%", label: "Native SwiftUI + AppKit. No Electron." },
];

const Card: React.FC<{ stat: Stat; frame: number; delay: number }> = ({
  stat,
  frame,
  delay,
}) => {
  const s = ramp(frame, delay, 30, [0.34, 1.4, 0.64, 1]);
  const count = interpolate(ramp(frame, delay + 8, 48), [0, 1], [0, stat.value]);
  const shown = stat.decimals ? count.toFixed(stat.decimals) : Math.round(count).toString();

  return (
    <div
      style={{
        flex: 1,
        padding: "40px 30px",
        borderRadius: 22,
        background: "rgba(16,21,31,0.72)",
        border: "1px solid rgba(255,255,255,0.08)",
        boxShadow: "0 30px 70px -30px rgba(0,0,0,0.7), inset 0 1px 0 rgba(255,255,255,0.05)",
        transform: `translateY(${(1 - s) * 40}px) scale(${0.9 + s * 0.1})`,
        opacity: s,
        textAlign: "center",
      }}
    >
      <div
        style={{
          fontFamily: inter,
          fontSize: 84,
          fontWeight: 800,
          letterSpacing: -2,
          lineHeight: 1,
          ...(stat.gradient
            ? {
                background: ACCENT_GRAD,
                WebkitBackgroundClip: "text",
                WebkitTextFillColor: "transparent",
                backgroundClip: "text",
              }
            : { color: c.text }),
        }}
      >
        {stat.prefix}
        {shown}
        {stat.suffix}
      </div>
      <div
        style={{
          marginTop: 18,
          fontFamily: inter,
          fontSize: 19,
          fontWeight: 500,
          color: c.textDim,
        }}
      >
        {stat.label}
      </div>
    </div>
  );
};

export const Stats: React.FC = () => {
  const frame = useCurrentFrame();

  const headO = interpolate(frame, [0, 20], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const headY = interpolate(frame, [0, 24], [22, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: Easing.bezier(...EASE_OUT),
  });
  const out = interpolate(frame, [275, 305], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  return (
    <AbsoluteFill
      style={{
        alignItems: "center",
        justifyContent: "center",
        opacity: 1 - out,
        transform: `scale(${1 + out * 0.04})`,
      }}
    >
      <div style={{ width: 1560 }}>
        <div
          style={{
            textAlign: "center",
            marginBottom: 56,
            opacity: headO,
            transform: `translateY(${headY}px)`,
          }}
        >
          <div
            style={{
              fontFamily: inter,
              fontSize: 16,
              fontWeight: 800,
              letterSpacing: 3,
              color: c.accent2,
              marginBottom: 14,
            }}
          >
            THE ABSENCE OF BLOAT
          </div>
          <div
            style={{
              fontFamily: inter,
              fontSize: 56,
              fontWeight: 700,
              color: c.text,
              letterSpacing: -1,
            }}
          >
            Just the editor and the tools you already have.
          </div>
        </div>
        <div style={{ display: "flex", gap: 24 }}>
          {STATS.map((st, i) => (
            <Card key={i} stat={st} frame={frame} delay={34 + i * 16} />
          ))}
        </div>
      </div>
    </AbsoluteFill>
  );
};
