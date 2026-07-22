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
    showCombo: true,
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
    CODEX_POWER_MODE_IDLE: "always",
    CODEX_POWER_MODE_LANGUAGE: "zh-CN",
    CODEX_POWER_MODE_ACTIVITY_SOURCE: "global",
    CODEX_POWER_MODE_INTENSITY: "high",
    CODEX_POWER_MODE_SHOW_COMBO: "0",
    CODEX_POWER_MODE_ENABLED: "0"
  }), {
    schemaVersion: 1,
    preset: "arcade",
    edge: "bottom-left",
    scale: 1.6,
    reducedMotion: true,
    inactiveBehavior: "follow",
    autoHideDelay: 6,
    enabled: false,
    idleBehavior: "always",
    language: "zh-CN",
    activitySource: "global",
    effectIntensity: "high",
    showCombo: false,
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
    showCombo: false,
    positionX: 0.42,
    positionY: 0.66
  };
  assert.deepEqual(nativeConfigFromEnvironment({}, stored), stored);
  assert.equal(nativeConfigFromEnvironment({ CODEX_POWER_MODE_PRESET: "focus" }, stored).preset, "focus");
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

test("native config deliberately resets pre-schema development settings", () => {
  const reset = nativeConfigFromEnvironment({}, { preset: "arcade", idleBehavior: "always", scale: 1.6 });
  assert.equal(reset.schemaVersion, 1);
  assert.equal(reset.preset, "focus");
  assert.equal(reset.idleBehavior, "hide");
  assert.equal(reset.scale, 1.15);
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
  assert.equal(upgraded.showCombo, true);
  assert.equal(upgraded.inactiveBehavior, "hide");
  assert.equal(upgraded.autoHideDelay, 2);
});

test("native config limits auto-hide delay to supported rhythm presets", () => {
  assert.equal(nativeConfigFromEnvironment({ CODEX_POWER_MODE_AUTO_HIDE_DELAY: "0" }).autoHideDelay, 0);
  assert.equal(nativeConfigFromEnvironment({ CODEX_POWER_MODE_AUTO_HIDE_DELAY: "2" }).autoHideDelay, 2);
  assert.equal(nativeConfigFromEnvironment({ CODEX_POWER_MODE_AUTO_HIDE_DELAY: "6" }).autoHideDelay, 6);
  assert.equal(nativeConfigFromEnvironment({ CODEX_POWER_MODE_AUTO_HIDE_DELAY: "99" }).autoHideDelay, 2);
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
