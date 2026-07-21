import assert from "node:assert/strict";
import test from "node:test";
import { isPowerModeServerCommand, serviceMatchesPlugin } from "../src/service-identity.mjs";

test("service identity requires both the current version and plugin root", () => {
  const identity = { version: "1.0.0+codex.current", root: "/tmp/current/codex-power-mode" };
  assert.equal(serviceMatchesPlugin({
    serviceVersion: identity.version,
    serviceRoot: identity.root
  }, identity), true);
  assert.equal(serviceMatchesPlugin({
    serviceVersion: "1.0.0+codex.old",
    serviceRoot: identity.root
  }, identity), false);
  assert.equal(serviceMatchesPlugin({
    serviceVersion: identity.version,
    serviceRoot: "/tmp/old/codex-power-mode"
  }, identity), false);
});

test("stale-service replacement only targets the Power Mode server command", () => {
  assert.equal(isPowerModeServerCommand(
    "/opt/node /Users/me/.codex/plugins/cache/personal/codex-power-mode/1/scripts/server.mjs --data-dir /tmp/data"
  ), true);
  assert.equal(isPowerModeServerCommand("node /tmp/unrelated/scripts/server.mjs"), false);
  assert.equal(isPowerModeServerCommand("node /tmp/codex-power-mode/scripts/demo.mjs"), false);
});
