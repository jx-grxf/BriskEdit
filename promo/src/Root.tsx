import "./index.css";
import { Composition } from "remotion";
import { BriskEditPromo, DURATION } from "./BriskEditPromo";

export const RemotionRoot: React.FC = () => {
  return (
    <Composition
      id="BriskEditPromo"
      component={BriskEditPromo}
      durationInFrames={DURATION}
      fps={60}
      width={1920}
      height={1080}
    />
  );
};
