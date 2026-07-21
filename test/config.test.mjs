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
    edge: "top-right",
    scale: 1.15,
    reducedMotion: false,
    followWhenInactive: false,
    enabled: true,
    idleBehavior: "hide",
    language: "auto",
    activitySource: "focused",
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
    CODEX_POWER_MODE_FOLLOW_WHEN_INACTIVE: "1",
    CODEX_POWER_MODE_IDLE: "always",
    CODEX_POWER_MODE_LANGUAGE: "zh-CN",
    CODEX_POWER_MODE_ACTIVITY_SOURCE: "global",
    CODEX_POWER_MODE_ENABLED: "0"
  }), {
    schemaVersion: 1,
    preset: "arcade",
    edge: "bottom-left",
    scale: 1.6,
    reducedMotion: true,
    followWhenInactive: true,
    enabled: false,
    idleBehavior: "always",
    language: "zh-CN",
    activitySource: "global",
    positionX: null,
    positionY: null
  });
  assert.equal(nativeConfigFromEnvironment({ CODEX_POWER_MODE_EDGE: "sideways" }).edge, "top-right");
});

test("native config preserves settings unless an environment override is provided", () => {
  const stored = {
    schemaVersion: 1,
    preset: "arcade",
    edge: "bottom-right",
    scale: 1.3,
    reducedMotion: true,
    followWhenInactive: true,
    enabled: false,
    idleBehavior: "orb",
    language: "en",
    activitySource: "global",
    positionX: 0.42,
    positionY: 0.66
  };
  assert.deepEqual(nativeConfigFromEnvironment({}, stored), stored);
  assert.equal(nativeConfigFromEnvironment({ CODEX_POWER_MODE_PRESET: "focus" }, stored).preset, "focus");
});

test("native config deliberately resets pre-schema development settings", () => {
  const reset = nativeConfigFromEnvironment({}, { preset: "arcade", idleBehavior: "always", scale: 1.6 });
  assert.equal(reset.schemaVersion, 1);
  assert.equal(reset.preset, "focus");
  assert.equal(reset.idleBehavior, "hide");
  assert.equal(reset.scale, 1.15);
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
