import test from "node:test";
import assert from "node:assert/strict";
import {
  nativeConfigFromEnvironment,
  nativeStreamEndpointFromEnvironment,
  serviceEndpointFromEnvironment,
  servicePortFromEnvironment
} from "../src/config.mjs";

test("native config reports defaults used by the overlay", () => {
  assert.deepEqual(nativeConfigFromEnvironment(), {
    schemaVersion: 1,
    preset: "focus",
    edge: "smart",
    scale: 1.15,
    reducedMotion: false,
    inactiveBehavior: "hide",
    autoHideDelay: 2,
    enabled: true,
    idleBehavior: "hide",
    language: "auto",
    activitySource: "focused",
    effectIntensity: "normal",
    energyGainMultiplier: 0.72,
    showCombo: true,
    typingCombo: false,
    cursorEffect: "spark",
    positionX: null,
    positionY: null
  });
});

test("native config normalizes environment overrides", () => {
  assert.deepEqual(nativeConfigFromEnvironment({
    CODEX_POWER_MODE_PRESET: "arcade",
    CODEX_POWER_MODE_EDGE: "bottom-left",
    CODEX_POWER_MODE_SCALE: "9",
    CODEX_POWER_MODE_REDUCED_MOTION: "1",
    CODEX_POWER_MODE_INACTIVE_BEHAVIOR: "follow",
    CODEX_POWER_MODE_AUTO_HIDE_DELAY: "6",
    CODEX_POWER_MODE_IDLE: "orb",
    CODEX_POWER_MODE_LANGUAGE: "zh-CN",
    CODEX_POWER_MODE_ACTIVITY_SOURCE: "global",
    CODEX_POWER_MODE_INTENSITY: "high",
    CODEX_POWER_MODE_ENERGY_GAIN: "1.15",
    CODEX_POWER_MODE_SHOW_COMBO: "0",
    CODEX_POWER_MODE_TYPING_COMBO: "1",
    CODEX_POWER_MODE_CURSOR_EFFECT: "neon",
    CODEX_POWER_MODE_ENABLED: "0"
  }), {
    schemaVersion: 1,
    preset: "arcade",
    edge: "bottom-left",
    scale: 1.6,
    reducedMotion: true,
    inactiveBehavior: "stay",
    autoHideDelay: 6,
    enabled: false,
    idleBehavior: "orb",
    language: "zh-CN",
    activitySource: "global",
    effectIntensity: "high",
    energyGainMultiplier: 1.15,
    showCombo: false,
    typingCombo: true,
    cursorEffect: "neon",
    positionX: null,
    positionY: null
  });
  assert.equal(nativeConfigFromEnvironment({ CODEX_POWER_MODE_EDGE: "smart" }).edge, "smart");
  assert.equal(nativeConfigFromEnvironment({ CODEX_POWER_MODE_EDGE: "sideways" }).edge, "smart");
});

test("native config preserves settings unless an environment override is provided", () => {
  const stored = {
    schemaVersion: 1,
    preset: "arcade",
    edge: "bottom-right",
    scale: 1.3,
    reducedMotion: true,
    inactiveBehavior: "stay",
    autoHideDelay: 0,
    enabled: false,
    idleBehavior: "orb",
    language: "en",
    activitySource: "global",
    effectIntensity: "low",
    energyGainMultiplier: 0.5,
    showCombo: false,
    typingCombo: true,
    cursorEffect: "spark",
    positionX: 0.42,
    positionY: 0.66
  };
  assert.deepEqual(nativeConfigFromEnvironment({}, stored), stored);
  assert.equal(nativeConfigFromEnvironment({ CODEX_POWER_MODE_PRESET: "focus" }, stored).preset, "focus");
});

test("native config preserves completed permission onboarding across restarts", () => {
  const restarted = nativeConfigFromEnvironment({}, {
    schemaVersion: 1,
    onboardingVersion: 1
  });
  assert.equal(restarted.onboardingVersion, 1);
});

test("native config accepts the shared Mix activity source", () => {
  assert.equal(nativeConfigFromEnvironment({ CODEX_POWER_MODE_ACTIVITY_SOURCE: "mix" }).activitySource, "mix");
});

test("classic Power Mode keeps only cursor feedback and forces Typing Combo on", () => {
  const classic = nativeConfigFromEnvironment({
    CODEX_POWER_MODE_PRESET: "classic",
    CODEX_POWER_MODE_TYPING_COMBO: "0"
  });
  assert.equal(classic.preset, "classic");
  assert.equal(classic.typingCombo, true);
});

test("native config accepts every cursor effect", () => {
  for (const cursorEffect of ["off", "spark", "neon", "orbit", "ripple", "prism", "wormhole", "glitch", "tentacle", "meme", "possum", "freshcat", "knifeshield", "elegant"]) {
    assert.equal(nativeConfigFromEnvironment({ CODEX_POWER_MODE_CURSOR_EFFECT: cursorEffect }).cursorEffect, cursorEffect);
  }
});

test("native config preserves an unset custom position across restarts", () => {
  const restarted = nativeConfigFromEnvironment({}, {
    schemaVersion: 1,
    edge: "top-right",
    positionX: null,
    positionY: null
  });
  assert.equal(restarted.edge, "top-right");
  assert.equal(restarted.positionX, null);
  assert.equal(restarted.positionY, null);
});

test("native config migrates the old inactive-window toggle into an explicit policy", () => {
  const visible = nativeConfigFromEnvironment({}, { schemaVersion: 1, followWhenInactive: true });
  const hidden = nativeConfigFromEnvironment({}, { schemaVersion: 1, followWhenInactive: false });
  assert.equal(visible.inactiveBehavior, "stay");
  assert.equal(hidden.inactiveBehavior, "hide");
  assert.equal(Object.hasOwn(visible, "followWhenInactive"), false);
});

test("native config migrates foreground-app following into a fixed on-screen HUD", () => {
  assert.equal(nativeConfigFromEnvironment({}, {
    schemaVersion: 1,
    inactiveBehavior: "follow"
  }).inactiveBehavior, "stay");
  assert.equal(nativeConfigFromEnvironment({
    CODEX_POWER_MODE_INACTIVE_BEHAVIOR: "follow"
  }).inactiveBehavior, "stay");
});

test("native config deliberately resets pre-schema development settings", () => {
  const reset = nativeConfigFromEnvironment({}, { preset: "arcade", idleBehavior: "always", scale: 1.6 });
  assert.equal(reset.schemaVersion, 1);
  assert.equal(reset.preset, "focus");
  assert.equal(reset.idleBehavior, "hide");
  assert.equal(reset.scale, 1.15);
});

test("native config migrates the removed expanded HUD to the quiet orb", () => {
  const upgraded = nativeConfigFromEnvironment({}, { schemaVersion: 1, idleBehavior: "always" });
  assert.equal(upgraded.idleBehavior, "orb");
});

test("native config adds display defaults without resetting older schema-one settings", () => {
  const upgraded = nativeConfigFromEnvironment({}, {
    schemaVersion: 1,
    preset: "arcade",
    edge: "top-left",
    scale: 1.3,
    idleBehavior: "orb"
  });
  assert.equal(upgraded.preset, "arcade");
  assert.equal(upgraded.edge, "top-left");
  assert.equal(upgraded.scale, 1.3);
  assert.equal(upgraded.idleBehavior, "orb");
  assert.equal(upgraded.effectIntensity, "normal");
  assert.equal(upgraded.energyGainMultiplier, 0.72);
  assert.equal(upgraded.showCombo, true);
  assert.equal(upgraded.typingCombo, false);
  assert.equal(upgraded.inactiveBehavior, "hide");
  assert.equal(upgraded.autoHideDelay, 2);
});

test("native config limits auto-hide delay to supported rhythm presets", () => {
  assert.equal(nativeConfigFromEnvironment({ CODEX_POWER_MODE_AUTO_HIDE_DELAY: "0" }).autoHideDelay, 0);
  assert.equal(nativeConfigFromEnvironment({ CODEX_POWER_MODE_AUTO_HIDE_DELAY: "2" }).autoHideDelay, 2);
  assert.equal(nativeConfigFromEnvironment({ CODEX_POWER_MODE_AUTO_HIDE_DELAY: "6" }).autoHideDelay, 6);
  assert.equal(nativeConfigFromEnvironment({ CODEX_POWER_MODE_AUTO_HIDE_DELAY: "99" }).autoHideDelay, 2);
});

test("native config limits Energy gain to supported live presets", () => {
  for (const multiplier of [0.3, 0.4, 0.5, 0.6, 0.72, 0.85, 1, 1.15, 1.3, 1.5]) {
    assert.equal(
      nativeConfigFromEnvironment({ CODEX_POWER_MODE_ENERGY_GAIN: String(multiplier) }).energyGainMultiplier,
      multiplier
    );
  }
  assert.equal(nativeConfigFromEnvironment({ CODEX_POWER_MODE_ENERGY_GAIN: "0.55" }).energyGainMultiplier, 0.5);
  assert.equal(nativeConfigFromEnvironment({ CODEX_POWER_MODE_ENERGY_GAIN: "0.9" }).energyGainMultiplier, 0.85);
  assert.equal(nativeConfigFromEnvironment({ CODEX_POWER_MODE_ENERGY_GAIN: "1.1" }).energyGainMultiplier, 1.15);
  assert.equal(nativeConfigFromEnvironment({ CODEX_POWER_MODE_ENERGY_GAIN: "0.73" }).energyGainMultiplier, 0.72);
});

test("service config keeps controllers and hooks on the configured port", () => {
  const environment = { CODEX_POWER_MODE_PORT: "5812" };
  assert.equal(servicePortFromEnvironment(environment), 5_812);
  assert.equal(serviceEndpointFromEnvironment(environment), "http://127.0.0.1:5812");
  assert.equal(nativeStreamEndpointFromEnvironment(environment), "http://127.0.0.1:5812/api/stream");
});

test("service config rejects invalid ports", () => {
  for (const value of ["0", "65536", "4737extra", "", undefined]) {
    assert.equal(servicePortFromEnvironment({ CODEX_POWER_MODE_PORT: value }), 4_737);
  }
});
