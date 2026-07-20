import test from "node:test";
import assert from "node:assert/strict";
import { comboProgress, initialState, reduceState, shouldCoalesceActivity } from "../src/state.mjs";

const at = (seconds) => new Date(seconds * 1_000).toISOString();

test("activity events represent Codex states without rewarding code volume", () => {
  const state = reduceState(initialState, {
    type: "activity-start", phase: "observe", toolGroup: "search", timestamp: at(1), sessionId: "s"
  });
  assert.equal(state.phase, "observe");
  assert.equal(state.momentum, 1);
  assert.equal(state.currentActivity, "Searching the workspace");
});

test("rapid identical observe activity is coalesced without hiding phase changes", () => {
  const previous = {
    ...initialState,
    lastActivityAt: at(1),
    lastActivitySignature: "observe:search:"
  };
  assert.equal(shouldCoalesceActivity(previous, {
    type: "activity-start", phase: "observe", toolGroup: "search", timestamp: at(1.5)
  }, 900), true);
  assert.equal(shouldCoalesceActivity(previous, {
    type: "activity-start", phase: "act", toolGroup: "change", timestamp: at(1.5)
  }, 900), false);
  assert.equal(shouldCoalesceActivity(previous, {
    type: "activity-start", phase: "observe", toolGroup: "search", timestamp: at(2)
  }, 900), false);
});

test("small and large edits earn equal momentum while scope changes risk", () => {
  const small = reduceState(initialState, {
    type: "edit", timestamp: at(2), addedLines: 2, removedLines: 0, addedChars: 20
  });
  const large = reduceState(initialState, {
    type: "edit", timestamp: at(2), addedLines: 200, removedLines: 0, addedChars: 4_000
  });
  assert.equal(small.momentum, large.momentum);
  assert.ok(large.risk > small.risk);
  assert.equal(small.phase, "act");
});

test("permission requests enter an explicit attention state", () => {
  const state = reduceState(initialState, { type: "permission-request", timestamp: at(2) });
  assert.equal(state.phase, "wait");
  assert.equal(state.status, "needs-attention");
});

test("failed verification enters recovery and raises risk", () => {
  const state = reduceState({ ...initialState, momentum: 20, confidence: 40 }, {
    type: "verification", category: "test", success: false, timestamp: at(3)
  });
  assert.equal(state.phase, "recover");
  assert.equal(state.momentum, 12);
  assert.equal(state.confidence, 12);
  assert.ok(state.risk > 0);
});

test("successful verification creates evidence and confidence", () => {
  const state = reduceState(initialState, {
    type: "verification", category: "test", success: true, timestamp: at(3)
  });
  assert.equal(state.phase, "verify");
  assert.equal(state.confidence, 38);
  assert.deepEqual(state.evidence, ["test"]);
});

test("turn completes as verified only after post-edit evidence", () => {
  let state = reduceState(initialState, {
    type: "edit", timestamp: at(2), addedLines: 2, removedLines: 0, addedChars: 20
  });
  state = reduceState(state, {
    type: "verification", category: "test", success: true, timestamp: at(3)
  });
  state = reduceState(state, { type: "turn-stop", timestamp: at(4) });
  assert.equal(state.phase, "complete");
  assert.equal(state.completion, "verified");
});

test("unverified edits cannot claim an evidence-backed completion", () => {
  let state = reduceState(initialState, {
    type: "edit", timestamp: at(2), addedLines: 2, removedLines: 0, addedChars: 20
  });
  state = reduceState(state, { type: "turn-stop", timestamp: at(3) });
  assert.equal(state.completion, "unverified");
  assert.equal(state.status, "unverified");
});

test("combo holds during tools and then decays after a useful result", () => {
  let state = reduceState(initialState, {
    type: "activity-start", phase: "act", toolGroup: "change", timestamp: at(1), sessionId: "s"
  });
  assert.equal(state.combo, 1);
  assert.equal(state.comboStatus, "holding");
  assert.equal(comboProgress(state, at(10)), 1);

  state = reduceState(state, {
    type: "edit", timestamp: at(12), addedLines: 3, removedLines: 0, sessionId: "s"
  });
  assert.equal(state.combo, 2);
  assert.equal(state.comboStatus, "decaying");
  assert.equal(comboProgress(state, at(18)), 0.5);
  assert.equal(comboProgress(state, at(24)), 0);
});

test("an expired combo restarts instead of increasing forever", () => {
  let state = reduceState(initialState, {
    type: "activity-start", phase: "observe", toolGroup: "search", timestamp: at(1), sessionId: "s"
  });
  state = reduceState(state, {
    type: "activity-start", phase: "observe", toolGroup: "search", timestamp: at(20), sessionId: "s"
  });
  assert.equal(state.combo, 1);
  assert.equal(state.comboBreaks, 1);
});

test("failed verification immediately breaks the combo", () => {
  let state = reduceState(initialState, {
    type: "activity-start", phase: "verify", category: "test", timestamp: at(1), sessionId: "s"
  });
  state = reduceState(state, {
    type: "verification", category: "test", success: false, timestamp: at(3), sessionId: "s"
  });
  assert.equal(state.combo, 0);
  assert.equal(state.comboStatus, "broken");
  assert.equal(state.comboBreaks, 1);
});

test("a new turn and a new session cannot inherit the previous combo", () => {
  let state = reduceState(initialState, {
    type: "activity-start", phase: "act", timestamp: at(1), sessionId: "s1"
  });
  state = reduceState(state, { type: "turn-stop", timestamp: at(2), sessionId: "s1" });
  state = reduceState(state, {
    type: "activity-start", phase: "observe", timestamp: at(3), sessionId: "s1"
  });
  assert.equal(state.combo, 1);

  state = reduceState(state, {
    type: "activity-start", phase: "observe", timestamp: at(4), sessionId: "s2"
  });
  assert.equal(state.combo, 1);
  assert.equal(state.comboBreaks, 0);
});
