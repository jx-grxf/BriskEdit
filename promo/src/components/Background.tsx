import { AbsoluteFill, useCurrentFrame } from "remotion";
import { c } from "../theme";

/**
 * Persistent atmospheric backdrop: deep gradient + two slow-drifting accent
 * glows + a faint dot grid. Everything is frame-driven (no CSS animation).
 */
export const Background: React.FC = () => {
  const frame = useCurrentFrame();
  const t = frame / 60;

  const g1x = 50 + Math.sin(t * 0.5) * 14;
  const g1y = 30 + Math.cos(t * 0.4) * 10;
  const g2x = 70 + Math.cos(t * 0.33) * 16;
  const g2y = 78 + Math.sin(t * 0.45) * 10;

  return (
    <AbsoluteFill style={{ backgroundColor: c.bg0 }}>
      <AbsoluteFill
        style={{
          background: `radial-gradient(120% 90% at 50% -10%, ${c.bg1} 0%, ${c.bg0} 60%)`,
        }}
      />
      <AbsoluteFill
        style={{
          background: `radial-gradient(38% 38% at ${g1x}% ${g1y}%, rgba(91,140,255,0.22), transparent 70%)`,
        }}
      />
      <AbsoluteFill
        style={{
          background: `radial-gradient(40% 40% at ${g2x}% ${g2y}%, rgba(86,225,224,0.16), transparent 70%)`,
        }}
      />
      {/* faint dot grid */}
      <AbsoluteFill
        style={{
          backgroundImage:
            "radial-gradient(rgba(255,255,255,0.045) 1px, transparent 1px)",
          backgroundSize: "44px 44px",
          maskImage:
            "radial-gradient(120% 80% at 50% 40%, black 30%, transparent 80%)",
          WebkitMaskImage:
            "radial-gradient(120% 80% at 50% 40%, black 30%, transparent 80%)",
        }}
      />
      {/* top + bottom vignette for cinematic falloff */}
      <AbsoluteFill
        style={{
          background:
            "linear-gradient(180deg, rgba(0,0,0,0.35) 0%, transparent 18%, transparent 82%, rgba(0,0,0,0.5) 100%)",
        }}
      />
    </AbsoluteFill>
  );
};
