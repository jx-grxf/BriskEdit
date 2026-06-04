import { interpolate } from "remotion";
import { c, inter, mono, WARM_GRAD } from "../theme";
import { CodeView } from "./CodeView";

export type WindowState = {
  chars: number;
  completion?: number; // 0..1
  diagnostic?: number; // 0..1
  runGlow?: number; // 0..1
  terminal?: number; // 0..1 (panel reveal)
  terminalChars?: number;
  cursorBlink?: boolean;
};

const WIN_W = 1480;
const WIN_H = 906;

const TrafficLight: React.FC<{ color: string }> = ({ color }) => (
  <div
    style={{
      width: 14,
      height: 14,
      borderRadius: 7,
      background: color,
      boxShadow: "inset 0 0 0 0.5px rgba(0,0,0,0.25)",
    }}
  />
);

const FileRow: React.FC<{
  name: string;
  depth: number;
  dot?: string;
  folder?: boolean;
  open?: boolean;
  active?: boolean;
  modified?: boolean;
}> = ({ name, depth, dot, folder, open, active, modified }) => (
  <div
    style={{
      display: "flex",
      alignItems: "center",
      height: 32,
      paddingLeft: 16 + depth * 18,
      gap: 8,
      borderRadius: 7,
      background: active ? "rgba(91,140,255,0.18)" : "transparent",
      boxShadow: active ? "inset 0 0 0 1px rgba(91,140,255,0.35)" : "none",
      color: active ? c.text : c.textDim,
      fontFamily: inter,
      fontSize: 16,
      fontWeight: active ? 600 : 500,
    }}
  >
    {folder ? (
      <span style={{ color: c.textFaint, fontSize: 11, width: 10 }}>
        {open ? "▾" : "▸"}
      </span>
    ) : (
      <span
        style={{
          width: 10,
          height: 10,
          borderRadius: 3,
          background: dot ?? c.textFaint,
          flexShrink: 0,
        }}
      />
    )}
    <span style={{ flex: 1 }}>{name}</span>
    {modified && (
      <span
        style={{
          width: 7,
          height: 7,
          borderRadius: 4,
          background: c.accent2,
          marginRight: 12,
        }}
      />
    )}
  </div>
);

const Tab: React.FC<{ name: string; dot: string; active?: boolean }> = ({
  name,
  dot,
  active,
}) => (
  <div
    style={{
      display: "flex",
      alignItems: "center",
      gap: 9,
      height: 42,
      padding: "0 20px",
      fontFamily: inter,
      fontSize: 15,
      fontWeight: active ? 600 : 500,
      color: active ? c.text : c.textDim,
      background: active ? c.editor : "transparent",
      borderRight: "1px solid rgba(255,255,255,0.05)",
      borderTop: active ? `2px solid ${c.accent}` : "2px solid transparent",
      position: "relative",
    }}
  >
    <span
      style={{ width: 9, height: 9, borderRadius: 3, background: dot }}
    />
    {name}
  </div>
);

export const Window: React.FC<WindowState> = ({
  chars,
  completion = 0,
  diagnostic = 0,
  runGlow = 0,
  terminal = 0,
  terminalChars = 0,
  cursorBlink = false,
}) => {
  const termH = interpolate(terminal, [0, 1], [0, 250]);
  const compOpacity = completion;
  const compY = interpolate(completion, [0, 1], [10, 0]);

  const runBg = runGlow > 0.5 ? WARM_GRAD : "rgba(255,255,255,0.07)";
  const runColor = runGlow > 0.5 ? "#fff" : c.text;

  const termLines = [
    [{ t: "~/briskedit ", c: c.green }, { t: "❯ ", c: c.accent2 }, { t: "swift Editor.swift", c: c.text }],
    [{ t: "ready in 0.011 s", c: c.textDim }],
    [{ t: "~/briskedit ", c: c.green }, { t: "❯ ", c: c.accent2 }],
  ];
  const termTotal = termLines.reduce(
    (s, l) => s + l.reduce((a, p) => a + p.t.length, 0) + 1,
    0,
  );
  let tc = 0;

  return (
    <div
      style={{
        width: WIN_W,
        height: WIN_H,
        borderRadius: 18,
        overflow: "hidden",
        background: "rgba(16,21,31,0.86)",
        backdropFilter: "blur(40px)",
        boxShadow:
          "0 60px 140px -30px rgba(0,0,0,0.8), 0 0 0 1px rgba(255,255,255,0.08), inset 0 1px 0 rgba(255,255,255,0.06)",
        display: "flex",
        flexDirection: "column",
      }}
    >
      {/* Title bar */}
      <div
        style={{
          height: 46,
          flexShrink: 0,
          display: "flex",
          alignItems: "center",
          padding: "0 18px",
          background: "rgba(255,255,255,0.025)",
          borderBottom: "1px solid rgba(255,255,255,0.05)",
        }}
      >
        <div style={{ display: "flex", gap: 9 }}>
          <TrafficLight color="#FF5F57" />
          <TrafficLight color="#FEBC2E" />
          <TrafficLight color="#28C840" />
        </div>
        <div
          style={{
            position: "absolute",
            left: 0,
            right: 0,
            textAlign: "center",
            fontFamily: inter,
            fontSize: 14,
            fontWeight: 600,
            color: c.textDim,
            pointerEvents: "none",
          }}
        >
          BriskEdit — Editor.swift
        </div>
        <div style={{ flex: 1 }} />
        {/* Run button */}
        <div
          style={{
            display: "flex",
            alignItems: "center",
            gap: 8,
            height: 30,
            padding: "0 16px",
            borderRadius: 9,
            background: runBg,
            color: runColor,
            fontFamily: inter,
            fontSize: 14,
            fontWeight: 700,
            boxShadow:
              runGlow > 0.5
                ? `0 0 0 1px rgba(242,104,58,0.5), 0 8px 24px -6px rgba(242,104,58,${0.6 * runGlow})`
                : "inset 0 0 0 1px rgba(255,255,255,0.08)",
          }}
        >
          <span style={{ fontSize: 11 }}>▶</span> Run
        </div>
      </div>

      {/* Body */}
      <div style={{ flex: 1, display: "flex", minHeight: 0 }}>
        {/* Sidebar */}
        <div
          style={{
            width: 256,
            flexShrink: 0,
            background: "rgba(12,16,24,0.6)",
            borderRight: "1px solid rgba(255,255,255,0.05)",
            padding: "14px 10px",
          }}
        >
          <div
            style={{
              fontFamily: inter,
              fontSize: 11,
              fontWeight: 700,
              letterSpacing: 1.4,
              color: c.textFaint,
              padding: "0 8px 10px",
            }}
          >
            BRISKEDIT
          </div>
          <FileRow name="Sources" depth={0} folder open />
          <FileRow name="Editor.swift" depth={1} dot={c.warm} active modified />
          <FileRow name="main.c" depth={1} dot="#7CC4FF" />
          <FileRow name="util.py" depth={1} dot="#FFD23F" />
          <FileRow name="server.go" depth={1} dot="#56E1E0" />
          <FileRow name="Tests" depth={0} folder />
          <FileRow name="Package.swift" depth={0} dot={c.warm} />
          <FileRow name="README.md" depth={0} dot={c.textDim} />
        </div>

        {/* Main column */}
        <div style={{ flex: 1, display: "flex", flexDirection: "column", minWidth: 0 }}>
          {/* Tabs */}
          <div
            style={{
              height: 42,
              flexShrink: 0,
              display: "flex",
              background: "rgba(10,13,20,0.5)",
              borderBottom: "1px solid rgba(255,255,255,0.05)",
            }}
          >
            <Tab name="Editor.swift" dot={c.warm} active />
            <Tab name="main.c" dot="#7CC4FF" />
            <Tab name="util.py" dot="#FFD23F" />
          </div>

          {/* Editor + terminal */}
          <div style={{ flex: 1, display: "flex", flexDirection: "column", minHeight: 0 }}>
            <div
              style={{
                flex: 1,
                position: "relative",
                background: c.editor,
                padding: "20px 0 0 6px",
                overflow: "hidden",
              }}
            >
              <CodeView
                visibleChars={chars}
                errorLine={diagnostic > 0.3 ? 4 : undefined}
              />

              {/* blinking end caret after typing done */}
              {cursorBlink && (
                <div
                  style={{
                    position: "absolute",
                    left: 52,
                    bottom: termH > 0 ? 18 : 22,
                    display: "none",
                  }}
                />
              )}

              {/* Completion popup */}
              {completion > 0.01 && (
                <div
                  style={{
                    position: "absolute",
                    left: 200,
                    top: 250,
                    width: 360,
                    opacity: compOpacity,
                    transform: `translateY(${compY}px)`,
                    background: "rgba(20,26,38,0.97)",
                    borderRadius: 12,
                    border: "1px solid rgba(255,255,255,0.1)",
                    boxShadow: "0 30px 70px -20px rgba(0,0,0,0.85)",
                    overflow: "hidden",
                    fontFamily: mono,
                    fontSize: 16,
                  }}
                >
                  {[
                    { n: "open(_ path:)", t: "Bool", sel: true },
                    { n: "openQuickly()", t: "Void", sel: false },
                    { n: "openRecent()", t: "[URL]", sel: false },
                    { n: "isOpen", t: "Bool", sel: false },
                  ].map((it, i) => (
                    <div
                      key={i}
                      style={{
                        display: "flex",
                        alignItems: "center",
                        gap: 12,
                        padding: "9px 14px",
                        background: it.sel ? "rgba(91,140,255,0.22)" : "transparent",
                      }}
                    >
                      <span
                        style={{
                          width: 20,
                          height: 20,
                          borderRadius: 5,
                          background: "rgba(210,168,255,0.2)",
                          color: c.synFunc,
                          fontSize: 12,
                          fontWeight: 700,
                          display: "flex",
                          alignItems: "center",
                          justifyContent: "center",
                        }}
                      >
                        ƒ
                      </span>
                      <span style={{ color: it.sel ? c.text : c.textDim, flex: 1 }}>
                        {it.n}
                      </span>
                      <span style={{ color: c.synType, fontSize: 14 }}>{it.t}</span>
                    </div>
                  ))}
                  <div
                    style={{
                      padding: "7px 14px",
                      fontSize: 12,
                      color: c.textFaint,
                      borderTop: "1px solid rgba(255,255,255,0.06)",
                      fontFamily: inter,
                    }}
                  >
                    sourcekit-lsp
                  </div>
                </div>
              )}
            </div>

            {/* Terminal panel */}
            {terminal > 0.01 && (
              <div
                style={{
                  height: termH,
                  flexShrink: 0,
                  background: c.panel,
                  borderTop: "1px solid rgba(255,255,255,0.07)",
                  overflow: "hidden",
                }}
              >
                <div
                  style={{
                    height: 34,
                    display: "flex",
                    alignItems: "center",
                    gap: 18,
                    padding: "0 18px",
                    borderBottom: "1px solid rgba(255,255,255,0.05)",
                    fontFamily: inter,
                    fontSize: 12,
                    fontWeight: 600,
                  }}
                >
                  <span style={{ color: c.text }}>TERMINAL</span>
                  <span style={{ color: c.textFaint }}>PROBLEMS</span>
                  <span style={{ color: c.textFaint }}>OUTPUT</span>
                  <div style={{ flex: 1 }} />
                  <span style={{ color: c.textFaint }}>zsh — briskedit</span>
                </div>
                <div
                  style={{
                    padding: "12px 18px",
                    fontFamily: mono,
                    fontSize: 16,
                    lineHeight: "26px",
                    whiteSpace: "pre",
                  }}
                >
                  {termLines.map((line, li) => {
                    const parts: React.ReactNode[] = [];
                    line.forEach((p, pi) => {
                      const shown =
                        tc >= terminalChars
                          ? ""
                          : tc + p.t.length <= terminalChars
                            ? p.t
                            : p.t.slice(0, terminalChars - tc);
                      tc += p.t.length;
                      if (shown)
                        parts.push(
                          <span key={pi} style={{ color: p.c }}>
                            {shown}
                          </span>,
                        );
                    });
                    tc += 1; // newline
                    const isLast = li === termLines.length - 1;
                    return (
                      <div key={li}>
                        {parts}
                        {isLast && terminalChars >= termTotal - 2 && (
                          <span style={{ color: c.accent2 }}>▮</span>
                        )}
                      </div>
                    );
                  })}
                </div>
              </div>
            )}
          </div>
        </div>
      </div>

      {/* Status bar */}
      <div
        style={{
          height: 32,
          flexShrink: 0,
          display: "flex",
          alignItems: "center",
          gap: 20,
          padding: "0 16px",
          background: "rgba(12,16,24,0.7)",
          borderTop: "1px solid rgba(255,255,255,0.05)",
          fontFamily: inter,
          fontSize: 12.5,
          fontWeight: 500,
          color: c.textDim,
        }}
      >
        <span style={{ color: c.green }}>⎇ main</span>
        {diagnostic > 0.3 ? (
          <span style={{ color: c.warm, fontWeight: 600 }}>
            ⚠ 1 warning
          </span>
        ) : (
          <span style={{ color: c.green }}>✓ no issues</span>
        )}
        <div style={{ flex: 1 }} />
        <span>Swift</span>
        <span>UTF-8</span>
        <span>LF</span>
        <span>Ln 13, Col 1</span>
      </div>
    </div>
  );
};

export { WIN_W, WIN_H };
