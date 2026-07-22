import assert from "node:assert/strict";
import test from "node:test";
import { refreshDelayForState } from "../overlay/refresh-cadence.mjs";

test("hidden online HUD sleeps until an external event wakes it", () => {
  assert.equal(refreshDelayForState({ connectionOnline: true, hudHidden: true }), null);
});

test("dynamic energy and Combo use responsive refresh cadence", () => {
  assert.equal(refreshDelayForState({ comboChanging: true }), 100);
  assert.equal(refreshDelayForState({ momentumChanging: true }), 100);
});

test("static and disconnected HUDs retain a low-frequency heartbeat", () => {
  assert.equal(refreshDelayForState(), 1_000);
  assert.equal(refreshDelayForState({ hudHidden: true, connectionOnline: false }), 1_000);
  assert.equal(refreshDelayForState({ previewMode: true, connectionOnline: true, hudHidden: true }), 1_000);
});
