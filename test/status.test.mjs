import assert from "node:assert/strict";
import test from "node:test";
import { powerModeStatus } from "../src/status.mjs";

test("status output distinguishes HUD display from raw task state", () => {
  const taskState = {
    phase: "complete",
    status: "complete",
    momentum: 22,
    combo: 0,
    comboStatus: "idle",
    turnStoppedAt: "2026-07-21T14:00:00.000Z",
    sessionId: "session-a",
    sessionSource: "desktop"
  };
  const snapshot = powerModeStatus({
    health: { clients: 1, activity: { lastRealEvent: null }, session: {} },
    nativePid: 42,
    nativeConfiguration: { preset: "focus" },
    state: taskState,
    endpoint: "http://127.0.0.1:4737"
  });

  assert.equal(snapshot.hudDisplay.phase, "idle");
  assert.equal(snapshot.hudDisplay.momentum, 0);
  assert.equal(snapshot.taskState.phase, "complete");
  assert.equal(snapshot.taskState.momentum, 22);
  assert.equal(Object.hasOwn(snapshot, "presentation"), false);
  assert.equal(Object.hasOwn(snapshot, "state"), false);
});
