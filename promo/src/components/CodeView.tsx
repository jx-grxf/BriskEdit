import { c, mono } from "../theme";

export type Tok = [string, string]; // [text, color]
export type Line = Tok[];

// Swift snippet shown typing in the editor (Run target = `swift`).
export const CODE: Line[] = [
  [["import", c.synKeyword], [" Foundation", c.synType]],
  [],
  [["struct", c.synKeyword], [" ", c.synPlain], ["Editor", c.synType], [" {", c.synPlain]],
  [
    ["    let", c.synKeyword],
    [" name ", c.synPlain],
    ["= ", c.synPlain],
    ['"BriskEdit"', c.synString],
  ],
  [],
  [
    ["    func", c.synKeyword],
    [" ", c.synPlain],
    ["open", c.synFunc],
    ["(_ path: ", c.synPlain],
    ["String", c.synType],
    [") -> ", c.synPlain],
    ["Bool", c.synType],
    [" {", c.synPlain],
  ],
  [["        // no indexing, no spinner", c.synComment]],
  [["        return ", c.synKeyword], ["true", c.synNumber]],
  [["    }", c.synPlain]],
  [["}", c.synPlain]],
  [],
  [
    ["let", c.synKeyword],
    [" app ", c.synPlain],
    ["= ", c.synPlain],
    ["Editor", c.synType],
    ["()", c.synPlain],
  ],
  [
    ["print", c.synFunc],
    ["(", c.synPlain],
    ['"ready in"', c.synString],
    [", ", c.synPlain],
    ["0.011", c.synNumber],
    [", ", c.synPlain],
    ['"s"', c.synString],
    [")", c.synPlain],
  ],
];

export const CODE_TOTAL_CHARS = CODE.reduce(
  (sum, line) =>
    sum + line.reduce((s, [txt]) => s + txt.length, 0) + 1, // +1 per newline
  0,
);

const FONT_SIZE = 25;
const LINE_H = 40;

type Props = {
  visibleChars: number;
  /** highlight a 1-based line (e.g. for a diagnostic squiggle) */
  errorLine?: number;
};

export const CodeView: React.FC<Props> = ({ visibleChars, errorLine }) => {
  let count = 0;
  const cursorPlaced = { done: false };

  return (
    <div
      style={{
        fontFamily: mono,
        fontSize: FONT_SIZE,
        lineHeight: `${LINE_H}px`,
        whiteSpace: "pre",
        position: "relative",
      }}
    >
      {CODE.map((line, li) => {
        const lineStart = count;
        const els: React.ReactNode[] = [];
        for (let ti = 0; ti < line.length; ti++) {
          const [txt, col] = line[ti];
          const shown =
            count >= visibleChars
              ? ""
              : count + txt.length <= visibleChars
                ? txt
                : txt.slice(0, visibleChars - count);
          count += txt.length;
          if (shown)
            els.push(
              <span key={ti} style={{ color: col }}>
                {shown}
              </span>,
            );
        }
        // newline char
        const lineEnd = count;
        count += 1;

        // place the typing cursor at the active line
        const cursorHere =
          !cursorPlaced.done &&
          visibleChars > lineStart &&
          visibleChars <= lineEnd + 1;
        if (cursorHere) cursorPlaced.done = true;

        const isError = errorLine === li + 1;

        return (
          <div
            key={li}
            style={{
              display: "flex",
              height: LINE_H,
              alignItems: "center",
              position: "relative",
            }}
          >
            <span
              style={{
                width: 46,
                flexShrink: 0,
                textAlign: "right",
                paddingRight: 22,
                color: isError ? c.warm : c.textFaint,
                userSelect: "none",
              }}
            >
              {li + 1}
            </span>
            <span style={{ position: "relative" }}>
              {els}
              {cursorHere && (
                <span
                  style={{
                    display: "inline-block",
                    width: 2.5,
                    height: FONT_SIZE,
                    background: c.accent2,
                    transform: "translateY(4px)",
                    marginLeft: 1,
                  }}
                />
              )}
              {isError && (
                <span
                  style={{
                    position: "absolute",
                    left: 0,
                    right: -4,
                    bottom: 4,
                    height: 3,
                    backgroundImage: `repeating-linear-gradient(135deg, ${c.warm} 0 3px, transparent 3px 6px)`,
                    borderRadius: 2,
                    opacity: 0.9,
                  }}
                />
              )}
            </span>
          </div>
        );
      })}
    </div>
  );
};
