import { AbsoluteFill, Easing, interpolate, useCurrentFrame } from "remotion";
import { c, inter, mono, ACCENT_GRAD, EASE_OUT } from "../theme";
import { ramp } from "../util";

type Feature = { badge: string; title: string; body: string };

const FEATURES: Feature[] = [
  { badge: "❯_", title: "Integrated terminal", body: "Real zsh, multiple tabs, follows your root" },
  { badge: "{}", title: "LSP completion", body: "From the servers already on your box" },
  { badge: "⌘P", title: "Go-to-File", body: "Fuzzy, instant, everything indexed" },
  { badge: "⇆", title: "Find & replace", body: "Regex, in-folder, .gitignore-aware" },
  { badge: "✓", title: "Format on save", body: "Your installed formatter, no config" },
  { badge: "↺", title: "Session restore", body: "Tabs and cursor, every launch" },
  { badge: "M↓", title: "Markdown preview", body: "Live split, scroll-synced, GFM" },
  { badge: "⌥", title: "Native macOS", body: "Menus, Services, Quick Look, Sparkle" },
];

const Card: React.FC<{ f: Feature; frame: number; delay: number }> = ({ f, frame, delay }) => {
  const s = ramp(frame, delay, 26, [0.34, 1.4, 0.64, 1]);
  if (s <= 0.001) return null;
  return (
    <div
      style={{
        display: "flex",
        gap: 16,
        alignItems: "flex-start",
        padding: "22px 22px",
        borderRadius: 18,
        background: "rgba(16,21,31,0.72)",
        border: "1px solid rgba(255,255,255,0.08)",
        boxShadow: "0 24px 50px -28px rgba(0,0,0,0.7), inset 0 1px 0 rgba(255,255,255,0.04)",
        transform: `translateY(${(1 - s) * 30}px) scale(${0.9 + s * 0.1})`,
        opacity: s,
      }}
    >
      <div
        style={{
          flexShrink: 0,
          width: 46,
          height: 46,
          borderRadius: 12,
          background: "rgba(91,140,255,0.14)",
          border: "1px solid rgba(91,140,255,0.3)",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          fontFamily: mono,
          fontSize: 18,
          fontWeight: 700,
          color: c.accent2,
        }}
      >
        {f.badge}
      </div>
      <div>
        <div style={{ fontFamily: inter, fontSize: 22, fontWeight: 700, color: c.text, marginBottom: 4 }}>
          {f.title}
        </div>
        <div style={{ fontFamily: inter, fontSize: 16, fontWeight: 500, color: c.textDim, lineHeight: 1.3 }}>
          {f.body}
        </div>
      </div>
    </div>
  );
};

export const FeatureGrid: React.FC = () => {
  const frame = useCurrentFrame();

  const headO = interpolate(frame, [0, 22], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  const headY = interpolate(frame, [0, 26], [22, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: Easing.bezier(...EASE_OUT),
  });
  const out = interpolate(frame, [385, 420], [0, 1], {
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
      <div style={{ width: 1500 }}>
        <div style={{ textAlign: "center", marginBottom: 48, opacity: headO, transform: `translateY(${headY}px)` }}>
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
            BUILT IN, NOT BOLTED ON
          </div>
          <div style={{ fontFamily: inter, fontSize: 52, fontWeight: 700, color: c.text, letterSpacing: -1 }}>
            Everything you need.{" "}
            <span
              style={{
                background: ACCENT_GRAD,
                WebkitBackgroundClip: "text",
                WebkitTextFillColor: "transparent",
                backgroundClip: "text",
              }}
            >
              Nothing you don't.
            </span>
          </div>
        </div>
        <div
          style={{
            display: "grid",
            gridTemplateColumns: "1fr 1fr",
            gap: 20,
          }}
        >
          {FEATURES.map((f, i) => (
            <Card key={f.title} f={f} frame={frame} delay={30 + i * 11} />
          ))}
        </div>
      </div>
    </AbsoluteFill>
  );
};
