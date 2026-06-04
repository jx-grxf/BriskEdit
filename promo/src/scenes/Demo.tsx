import { AbsoluteFill, Easing, interpolate, useCurrentFrame } from "remotion";
import { c, inter, EASE_OUT } from "../theme";
import { Window, WIN_W, WIN_H } from "../components/Window";
import { CODE_TOTAL_CHARS } from "../components/CodeView";
import { ramp, fadeInOut } from "../util";

type Beat = { kicker: string; title: string; from: number; to: number };

const BEATS: Beat[] = [
  { kicker: "INSTANT", title: "Opens before your finger leaves the trackpad", from: 30, to: 380 },
  { kicker: "INTELLIGENCE", title: "Completion from the language servers you already have", from: 380, to: 600 },
  { kicker: "LIVE DIAGNOSTICS", title: "Errors and warnings, right in the status bar", from: 600, to: 820 },
  { kicker: "RUN", title: "One button figures out the toolchain itself", from: 840, to: 1130 },
];

const Caption: React.FC<{ beat: Beat; frame: number }> = ({ beat, frame }) => {
  const o = interpolate(
    frame,
    [beat.from, beat.from + 16, beat.to - 18, beat.to],
    [0, 1, 1, 0],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: Easing.bezier(...EASE_OUT) },
  );
  const y = interpolate(frame, [beat.from, beat.from + 18], [16, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: Easing.bezier(...EASE_OUT),
  });
  if (o <= 0.001) return null;
  return (
    <div style={{ opacity: o, transform: `translateY(${y}px)`, textAlign: "center" }}>
      <div
        style={{
          fontFamily: inter,
          fontSize: 16,
          fontWeight: 800,
          letterSpacing: 3,
          color: c.accent2,
          marginBottom: 10,
        }}
      >
        {beat.kicker}
      </div>
      <div
        style={{
          fontFamily: inter,
          fontSize: 40,
          fontWeight: 700,
          color: c.text,
          letterSpacing: -0.5,
        }}
      >
        {beat.title}
      </div>
    </div>
  );
};

const LANGS: { name: string; dot: string }[] = [
  { name: "C / C++", dot: "#7CC4FF" },
  { name: "Swift", dot: c.warm },
  { name: "Python", dot: "#FFD23F" },
  { name: "JavaScript", dot: "#F0DB4F" },
  { name: "Rust", dot: "#FF8A65" },
  { name: "Go", dot: "#56E1E0" },
];

export const Demo: React.FC = () => {
  const frame = useCurrentFrame();

  // window entrance + exit
  const enter = ramp(frame, 0, 34);
  const exit = interpolate(frame, [1440, 1480], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: Easing.bezier(0.45, 0, 0.55, 1),
  });
  const winScale = interpolate(enter, [0, 1], [0.9, 0.8]) - exit * 0.04;
  const winOpacity = Math.min(enter, 1 - exit);
  const winY = interpolate(enter, [0, 1], [60, 36]) + exit * 30;

  // typing — slow enough to read the code go in
  const chars = interpolate(frame, [34, 380], [0, CODE_TOTAL_CHARS], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: Easing.bezier(0.5, 0, 0.5, 1),
  });

  const completion = fadeInOut(frame, 380, 600, 18, 20);
  const diagnostic = ramp(frame, 600, 28);
  const runGlow = fadeInOut(frame, 820, 1000, 16, 44);
  const terminal = ramp(frame, 900, 46);
  const terminalChars = interpolate(frame, [950, 1180], [0, 72], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  // language chips beat
  const chipsIn = ramp(frame, 1200, 32);
  const chipsOut = interpolate(frame, [1370, 1430], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const langCaptionO = interpolate(
    frame,
    [1200, 1228, 1370, 1418],
    [0, 1, 1, 0],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" },
  );

  return (
    <AbsoluteFill>
      {/* Window */}
      <AbsoluteFill style={{ alignItems: "center", justifyContent: "center" }}>
        <div
          style={{
            width: WIN_W,
            height: WIN_H,
            transform: `translateY(${winY}px) scale(${winScale})`,
            opacity: winOpacity,
          }}
        >
          <Window
            chars={chars}
            completion={completion}
            diagnostic={diagnostic}
            runGlow={runGlow}
            terminal={terminal}
            terminalChars={terminalChars}
          />
        </div>
      </AbsoluteFill>

      {/* Top caption band */}
      <div
        style={{
          position: "absolute",
          top: 56,
          left: 0,
          right: 0,
          height: 110,
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
        }}
      >
        {BEATS.map((b, i) => (
          <div key={i} style={{ position: "absolute" }}>
            <Caption beat={b} frame={frame} />
          </div>
        ))}
        {/* language headline reuses the band */}
        <div style={{ position: "absolute", opacity: langCaptionO, textAlign: "center" }}>
          <div
            style={{
              fontFamily: inter,
              fontSize: 16,
              fontWeight: 800,
              letterSpacing: 3,
              color: c.accent2,
              marginBottom: 10,
            }}
          >
            ZERO CONFIG
          </div>
          <div style={{ fontFamily: inter, fontSize: 40, fontWeight: 700, color: c.text }}>
            Uses the toolchains already on your Mac
          </div>
        </div>
      </div>

      {/* Language chips, bottom band */}
      <div
        style={{
          position: "absolute",
          bottom: 60,
          left: 0,
          right: 0,
          display: "flex",
          justifyContent: "center",
          gap: 16,
          opacity: Math.min(chipsIn, 1 - chipsOut),
        }}
      >
        {LANGS.map((l, i) => {
          const s = ramp(frame, 1205 + i * 9, 24, [0.34, 1.4, 0.64, 1]);
          return (
            <div
              key={l.name}
              style={{
                display: "flex",
                alignItems: "center",
                gap: 10,
                padding: "12px 22px",
                borderRadius: 14,
                background: "rgba(18,24,36,0.8)",
                border: "1px solid rgba(255,255,255,0.09)",
                boxShadow: "0 18px 40px -16px rgba(0,0,0,0.7)",
                fontFamily: inter,
                fontSize: 20,
                fontWeight: 600,
                color: c.text,
                transform: `translateY(${(1 - s) * 24}px) scale(${0.85 + s * 0.15})`,
                opacity: s,
              }}
            >
              <span style={{ width: 11, height: 11, borderRadius: 4, background: l.dot }} />
              {l.name}
            </div>
          );
        })}
      </div>
    </AbsoluteFill>
  );
};
