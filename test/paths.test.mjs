import assert from "node:assert/strict";
import test from "node:test";
import { powerModeDataDir } from "../src/paths.mjs";

test("manual runs keep runtime state outside the plugin source tree", () => {
  assert.equal(powerModeDataDir({}, "/Users/tester", () => false), "/Users/tester/.codex/power-mode");
});

test("plugin data takes precedence while explicit manual data remains supported", () => {
  assert.equal(powerModeDataDir({
    PLUGIN_DATA: "/tmp/plugin-data",
    CODEX_POWER_MODE_DATA: "/tmp/manual-data"
  }, "/Users/tester"), "/tmp/plugin-data");
  assert.equal(powerModeDataDir({
    CODEX_POWER_MODE_DATA: "/tmp/manual-data"
  }, "/Users/tester"), "/tmp/manual-data");
});

test("manual controllers reuse the installed plugin data directory", () => {
  const expected = "/Users/tester/.codex/plugins/data/codex-power-mode-personal";
  assert.equal(powerModeDataDir({}, "/Users/tester", (candidate) => candidate === expected), expected);
});
