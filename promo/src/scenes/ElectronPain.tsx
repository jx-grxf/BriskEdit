import {
  AbsoluteFill,
  Easing,
  interpolate,
  spring,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import { c, inter, mono } from "../theme";
import { ramp } from "../util";

const WIN_W = 1340;
const WIN_H = 820;

// VS Code-ish palette — recognizable so the joke lands.
const vs = {
  titleBar: "#323233",
  activity: "#2C2C2D",
  sidebar: "#252526",
  editor: "#1E1E1E",
  statusBlue: "#0E639C",
  line: "rgba(255,255,255,0.06)",
  text: "#CCCCCC",
  dim: "#7E7E7E",
  blue: "#3794FF",
  red: "#F14C4C",
  yellow: "#E5C07B",
};

const Spinner: React.FC<{ frame: number; size: number; stroke: number; color: string }> = ({
  frame,
  size,
  stroke,
  color,
}) => {
  const rot = (frame * 7) % 360;
  return (
    <div
      style={{
        width: size,
        height: size,
        borderRadius: "50%",
        border: `${stroke}px solid rgba(255,255,255,0.12)`,
        borderTopColor: color,
        transform: `rotate(${rot}deg)`,
      }}
    />
  );
};

const Toast: React.FC<{
  frame: number;
  from: number;
  title: string;
  body: string;
  accent: string;
  index: number;
}> = ({ frame, from, title, body, accent, index }) => {
  const inP = ramp(frame, from, 16, [0.34, 1.4, 0.64, 1]);
  if (inP <= 0.001) return null;
  const x = interpolate(inP, [0, 1], [340, 0]);
  // subtle nervous jitter to feel unstable
  const jit = Math.sin((frame + index * 9) / 3.2) * (1.2 + index * 0.3);
  return (
    <div
      style={{
        transform: `translateX(${x + jit}px)`,
        opacity: inP,
        width: 320,
        background: "#252526",
        border: `1px solid ${vs.line}`,
        borderLeft: `3px solid ${accent}`,
        borderRadius: 6,
        padding: "12px 14px",
        boxShadow: "0 12px 30px -10px rgba(0,0,0,0.6)",
        fontFamily: inter,
      }}
    >
      <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 5 }}>
        <span style={{ color: accent, fontSize: 14 }}>⚠</span>
        <span style={{ color: vs.text, fontSize: 14, fontWeight: 600 }}>{title}</span>
      </div>
      <div style={{ color: vs.dim, fontSize: 12.5, lineHeight: 1.35 }}>{body}</div>
    </div>
  );
};

const Meter: React.FC<{
  label: string;
  value: string;
  pct: number;
  danger: boolean;
}> = ({ label, value, pct, danger }) => (
  <div style={{ width: 230 }}>
    <div
      style={{
        display: "flex",
        justifyContent: "space-between",
        fontFamily: mono,
        fontSize: 13,
        marginBottom: 6,
        color: danger ? vs.red : vs.dim,
      }}
    >
      <span>{label}</span>
      <span style={{ fontWeight: 700 }}>{value}</span>
    </div>
    <div
      style={{
        height: 8,
        borderRadius: 5,
        background: "rgba(255,255,255,0.08)",
        overflow: "hidden",
      }}
    >
      <div
        style={{
          height: "100%",
          width: `${pct * 100}%`,
          borderRadius: 5,
          background: danger
            ? "linear-gradient(90deg,#E5C07B,#F14C4C)"
            : "linear-gradient(90deg,#3794FF,#56E1E0)",
        }}
      />
    </div>
  </div>
);

export const ElectronPain: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  // window entrance
  const pop = spring({ frame, fps, config: { damping: 16, mass: 0.8 }, durationInFrames: 26 });
  const winScale = interpolate(pop, [0, 1], [0.94, 1]);

  // it tries to "settle" but never does — late shudder before exit
  const shudder =
    frame > 380 ? Math.sin(frame / 1.7) * interpolate(frame, [380, 470], [0, 4], { extrapolateRight: "clamp" }) : 0;

  // exit — gets yanked away (zoom + fade) as BriskEdit takes over
  const exit = interpolate(frame, [480, 528], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: Easing.bezier(0.5, 0, 0.75, 0),
  });
  const groupO = 1 - exit;
  const groupScale = winScale * (1 - exit * 0.12);

  // ballooning RAM: 312 MB → 2.34 GB
  const ramPct = ramp(frame, 30, 200, [0.4, 0, 0.2, 1]);
  const ramGB = interpolate(ramPct, [0, 1], [0.312, 2.34]);
  const ramLabel = ramGB < 1 ? `${Math.round(ramGB * 1000)} MB` : `${ramGB.toFixed(2)} GB`;

  // CPU thrash
  const cpuBase = ramp(frame, 36, 90);
  const cpu = Math.min(1, cpuBase * (0.7 + 0.3 * Math.abs(Math.sin(frame / 5))));
  const cpuLabel = `${Math.round(cpu * 397)} %`;

  // extension install crawl that stalls near the end
  const inst = interpolate(frame, [48, 420], [0, 0.71], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: Easing.bezier(0.3, 0.9, 0.7, 1),
  });

  // captions
  const cap1 = interpolate(frame, [12, 34, 210, 240], [0, 1, 1, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const cap2 = interpolate(frame, [236, 262, 440, 470], [0, 1, 1, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  return (
    <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", opacity: groupO }}>
      {/* mocking caption band */}
      <div
        style={{
          position: "absolute",
          top: 70,
          left: 0,
          right: 0,
          textAlign: "center",
        }}
      >
        <div style={{ position: "absolute", left: 0, right: 0, opacity: cap1 }}>
          <div
            style={{
              fontFamily: inter,
              fontSize: 16,
              fontWeight: 800,
              letterSpacing: 3,
              color: vs.red,
              marginBottom: 10,
            }}
          >
            MEANWHILE, IN ELECTRON
          </div>
          <div style={{ fontFamily: inter, fontSize: 42, fontWeight: 700, color: c.text }}>
            You opened <span style={{ color: vs.blue }}>one</span> file.
          </div>
        </div>
        <div style={{ position: "absolute", left: 0, right: 0, opacity: cap2 }}>
          <div
            style={{
              fontFamily: inter,
              fontSize: 16,
              fontWeight: 800,
              letterSpacing: 3,
              color: vs.red,
              marginBottom: 10,
            }}
          >
            2.3 GB OF RAM · 397% CPU · 4 EXTENSION HOSTS
          </div>
          <div style={{ fontFamily: inter, fontSize: 42, fontWeight: 700, color: c.text }}>
            …just to edit a typo.
          </div>
        </div>
      </div>

      {/* fake VS Code window */}
      <div
        style={{
          width: WIN_W,
          height: WIN_H,
          marginTop: 70,
          transform: `translateX(${shudder}px) scale(${groupScale})`,
          borderRadius: 12,
          overflow: "hidden",
          background: vs.editor,
          border: "1px solid rgba(255,255,255,0.08)",
          boxShadow: "0 50px 120px -30px rgba(0,0,0,0.8)",
          display: "flex",
          flexDirection: "column",
        }}
      >
        {/* title bar */}
        <div
          style={{
            height: 38,
            background: vs.titleBar,
            display: "flex",
            alignItems: "center",
            paddingLeft: 16,
            gap: 9,
            position: "relative",
            flexShrink: 0,
          }}
        >
          {["#FF5F57", "#FEBC2E", "#28C840"].map((col) => (
            <span key={col} style={{ width: 12, height: 12, borderRadius: 6, background: col }} />
          ))}
          <div
            style={{
              position: "absolute",
              left: 0,
              right: 0,
              textAlign: "center",
              fontFamily: inter,
              fontSize: 13,
              color: vs.dim,
            }}
          >
            typo.ts — my-project — Visual Studio Code
          </div>
        </div>

        <div style={{ flex: 1, display: "flex", minHeight: 0 }}>
          {/* activity bar */}
          <div
            style={{
              width: 52,
              background: vs.activity,
              display: "flex",
              flexDirection: "column",
              alignItems: "center",
              paddingTop: 14,
              gap: 20,
            }}
          >
            {[0, 1, 2, 3, 4, 5].map((i) => (
              <div
                key={i}
                style={{
                  width: 24,
                  height: 24,
                  borderRadius: 5,
                  background: i === 0 ? "rgba(255,255,255,0.16)" : "rgba(255,255,255,0.07)",
                }}
              />
            ))}
          </div>

          {/* sidebar */}
          <div style={{ width: 230, background: vs.sidebar, padding: "14px 12px", flexShrink: 0 }}>
            <div
              style={{
                fontFamily: inter,
                fontSize: 11,
                letterSpacing: 1,
                color: vs.dim,
                marginBottom: 14,
              }}
            >
              EXPLORER
            </div>
            {[0, 1, 2, 3, 4, 5, 6].map((i) => (
              <div
                key={i}
                style={{
                  height: 10,
                  borderRadius: 3,
                  background: "rgba(255,255,255,0.06)",
                  width: `${85 - i * 7}%`,
                  marginBottom: 13,
                  marginLeft: i % 3 === 0 ? 0 : 14,
                }}
              />
            ))}
          </div>

          {/* editor area — covered by the eternal loader */}
          <div
            style={{
              flex: 1,
              position: "relative",
              display: "flex",
              flexDirection: "column",
              alignItems: "center",
              justifyContent: "center",
              gap: 22,
            }}
          >
            <Spinner frame={frame} size={64} stroke={5} color={vs.blue} />
            <div style={{ fontFamily: inter, fontSize: 18, color: vs.text, fontWeight: 500 }}>
              Loading workspace…
            </div>
            <div style={{ fontFamily: mono, fontSize: 13, color: vs.dim }}>
              Activating extensions ({Math.round(inst * 47)}/47)
            </div>

            {/* perf HUD */}
            <div
              style={{
                position: "absolute",
                top: 22,
                right: 22,
                display: "flex",
                flexDirection: "column",
                gap: 16,
                padding: "16px 18px",
                borderRadius: 10,
                background: "rgba(0,0,0,0.35)",
                border: `1px solid ${vs.line}`,
              }}
            >
              <Meter label="MEMORY" value={ramLabel} pct={ramPct} danger={ramGB > 1} />
              <Meter label="CPU" value={cpuLabel} pct={Math.min(1, cpu)} danger={cpu > 0.6} />
            </div>

            {/* stacked crash toasts */}
            <div
              style={{
                position: "absolute",
                bottom: 20,
                right: 20,
                display: "flex",
                flexDirection: "column",
                gap: 10,
              }}
            >
              <Toast
                frame={frame}
                from={60}
                index={0}
                accent={vs.red}
                title="Extension host terminated"
                body="The window will reload to recover. (exit code 5)"
              />
              <Toast
                frame={frame}
                from={150}
                index={1}
                accent={vs.yellow}
                title="ESLint server crashed"
                body="Server crashed 5 times in the last 3 minutes."
              />
              <Toast
                frame={frame}
                from={300}
                index={2}
                accent={vs.red}
                title="Reload required"
                body="An extension wants to modify settings.json…"
              />
            </div>
          </div>
        </div>

        {/* status bar */}
        <div
          style={{
            height: 26,
            background: vs.statusBlue,
            display: "flex",
            alignItems: "center",
            paddingLeft: 14,
            gap: 18,
            fontFamily: inter,
            fontSize: 12.5,
            color: "#fff",
            flexShrink: 0,
          }}
        >
          <span style={{ display: "flex", alignItems: "center", gap: 7 }}>
            <Spinner frame={frame} size={11} stroke={2} color="#fff" />
            Initializing…
          </span>
          <span>⚠ 3</span>
          <span>✖ 1</span>
          <span style={{ marginLeft: "auto", marginRight: 16, opacity: 0.9 }}>
            {(inst * 100).toFixed(0)}% · {ramLabel}
          </span>
        </div>
      </div>
    </AbsoluteFill>
  );
};
