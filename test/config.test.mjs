import test from "node:test";
import assert from "node:assert/strict";
import { nativeConfigFromEnvironment } from "../src/config.mjs";

test("native config reports defaults used by the overlay", () => {
  assert.deepEqual(nativeConfigFromEnvironment(), {
    preset: "focus",
    edge: "top-right",
    scale: 1.15,
    reducedMotion: false,
    followWhenInactive: false
  });
});

test("native config normalizes environment overrides", () => {
  assert.deepEqual(nativeConfigFromEnvironment({
    CODEX_POWER_MODE_PRESET: "arcade",
    CODEX_POWER_MODE_EDGE: "bottom-left",
    CODEX_POWER_MODE_SCALE: "9",
    CODEX_POWER_MODE_REDUCED_MOTION: "1",
    CODEX_POWER_MODE_FOLLOW_WHEN_INACTIVE: "1"
  }), {
    preset: "arcade",
    edge: "bottom-left",
    scale: 1.6,
    reducedMotion: true,
    followWhenInactive: true
  });
  assert.equal(nativeConfigFromEnvironment({ CODEX_POWER_MODE_EDGE: "sideways" }).edge, "top-right");
});
