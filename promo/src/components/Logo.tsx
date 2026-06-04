import { Img, staticFile } from "remotion";

/**
 * BriskEdit app icon (the real 1024px AppIcon artwork). A soft glow sits behind
 * it for depth. `caretOn` is kept for API compatibility but unused.
 */
export const LogoMark: React.FC<{ size?: number; caretOn?: boolean }> = ({
  size = 120,
}) => {
  return (
    <div style={{ position: "relative", width: size, height: size }}>
      <div
        style={{
          position: "absolute",
          inset: "8%",
          borderRadius: "30%",
          background:
            "radial-gradient(circle, rgba(91,140,255,0.5), rgba(86,225,224,0.18) 60%, transparent 72%)",
          filter: `blur(${size * 0.16}px)`,
        }}
      />
      <Img
        src={staticFile("appicon.png")}
        style={{
          position: "relative",
          width: size,
          height: size,
          filter: "drop-shadow(0 24px 50px rgba(0,0,0,0.55))",
        }}
      />
    </div>
  );
};
