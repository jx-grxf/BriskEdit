import { AbsoluteFill, Sequence } from "remotion";
import { Background } from "./components/Background";
import { Sound } from "./components/Sound";
import { Intro } from "./scenes/Intro";
import { ElectronPain } from "./scenes/ElectronPain";
import { RescueBridge } from "./scenes/RescueBridge";
import { Demo } from "./scenes/Demo";
import { FeatureGrid } from "./scenes/FeatureGrid";
import { Stats } from "./scenes/Stats";
import { Outro } from "./scenes/Outro";
import { SCENES } from "./timeline";

export { DURATION } from "./timeline";

export const BriskEditPromo: React.FC = () => {
  return (
    <AbsoluteFill style={{ backgroundColor: "#070A10" }}>
      <Background />

      {/* 1 · Brand open */}
      <Sequence from={SCENES.intro} durationInFrames={360}>
        <Intro />
      </Sequence>

      {/* 2 · The Electron status quo */}
      <Sequence from={SCENES.electron} durationInFrames={530}>
        <ElectronPain />
      </Sequence>

      {/* 3 · The turn */}
      <Sequence from={SCENES.rescue} durationInFrames={190}>
        <RescueBridge />
      </Sequence>

      {/* 4 · The product in action */}
      <Sequence from={SCENES.demo} durationInFrames={1500}>
        <Demo />
      </Sequence>

      {/* 5 · Breadth */}
      <Sequence from={SCENES.features} durationInFrames={440}>
        <FeatureGrid />
      </Sequence>

      {/* 6 · The pitch */}
      <Sequence from={SCENES.stats} durationInFrames={320}>
        <Stats />
      </Sequence>

      {/* 7 · CTA */}
      <Sequence from={SCENES.outro} durationInFrames={320}>
        <Outro />
      </Sequence>

      <Sound />
    </AbsoluteFill>
  );
};
