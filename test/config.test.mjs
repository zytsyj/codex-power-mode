import test from "node:test";
import assert from "node:assert/strict";
import {
  nativeConfigFromEnvironment,
  nativeStreamEndpointFromConfiguration,
  nativeStreamEndpointFromEnvironment,
  serviceEndpointFromEnvironment,
  servicePortFromEnvironment
} from "../src/config.mjs";

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

test("legacy native config remains attached to the default stream", () => {
  assert.equal(nativeStreamEndpointFromConfiguration({ preset: "focus" }), "http://127.0.0.1:4737/api/stream");
  assert.equal(
    nativeStreamEndpointFromConfiguration({ endpoint: "http://127.0.0.1:5812/api/stream" }),
    "http://127.0.0.1:5812/api/stream"
  );
});
