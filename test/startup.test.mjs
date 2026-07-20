import assert from "node:assert/strict";
import test from "node:test";
import { startupMode } from "../src/startup.mjs";

test("automatically starts the native overlay on macOS", () => {
  assert.equal(startupMode("darwin", {}), "native");
});

test("allows automatic native startup to be disabled", () => {
  assert.equal(startupMode("darwin", { CODEX_POWER_MODE_AUTO_NATIVE: "0" }), "start");
});

test("starts only the event service on non-macOS platforms", () => {
  assert.equal(startupMode("linux", {}), "start");
});
