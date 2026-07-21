import test from "node:test";
import assert from "node:assert/strict";
import { comboDisplayStatus, comboProgress, initialState, presentationSnapshot, reduceState, shouldCoalesceActivity } from "../src/state.mjs";

const at = (seconds) => new Date(seconds * 1_000).toISOString();

test("activity events represent Codex states without rewarding code volume", () => {
  const state = reduceState(initialState, {
    type: "activity-start", phase: "observe", toolGroup: "search", timestamp: at(1), sessionId: "s"
  });
  assert.equal(state.phase, "observe");
  assert.equal(state.momentum, 1);
  assert.equal(state.currentActivity, "Searching the workspace");
});

test("prompt submission immediately enters understanding", () => {
  const state = reduceState(initialState, {
    type: "activity-start", phase: "observe", toolGroup: "prompt", timestamp: at(1), sessionId: "s"
  });
  assert.equal(state.phase, "observe");
  assert.equal(state.currentActivity, "Understanding request");
  assert.equal(state.momentum, 1);
  assert.equal(state.combo, 1);
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
  assert.equal(state.turnStoppedAt, at(4));
});

test("a completed turn becomes idle only after combo feedback and returns momentum to zero", () => {
  let state = reduceState(initialState, {
    type: "edit", timestamp: at(2), addedLines: 2, removedLines: 0, sessionId: "s"
  });
  state = reduceState(state, {
    type: "verification", category: "test", success: true, timestamp: at(3), sessionId: "s"
  });
  state = reduceState(state, { type: "turn-stop", timestamp: at(4), sessionId: "s" });

  assert.equal(presentationSnapshot(state, at(22)).phase, "complete");
  const returning = presentationSnapshot(state, at(24.4));
  assert.equal(returning.phase, "idle");
  assert.equal(returning.status, "ready");
  assert.ok(returning.momentum > 0 && returning.momentum < state.momentum);
  const settled = presentationSnapshot(state, at(27));
  assert.equal(settled.momentum, 0);
  assert.equal(settled.settled, true);
  assert.equal(state.bestMomentum, settled.bestMomentum);
});

test("new work cancels the idle countdown", () => {
  let state = reduceState(initialState, { type: "turn-stop", timestamp: at(2), sessionId: "s" });
  state = reduceState(state, {
    type: "activity-start", phase: "observe", toolGroup: "search", timestamp: at(3), sessionId: "s"
  });
  assert.equal(state.turnStoppedAt, null);
  assert.equal(presentationSnapshot(state, at(30)).phase, "observe");
  assert.equal(state.momentum, 1);
  assert.equal(state.combo, 1);
});

test("a new turn resets current energy, evidence, risk, and edit scope while preserving records", () => {
  let state = reduceState(initialState, {
    type: "activity-start", phase: "act", toolGroup: "change", timestamp: at(1), sessionId: "s"
  });
  state = reduceState(state, { type: "edit", timestamp: at(2), addedLines: 80, removedLines: 4, sessionId: "s" });
  state = reduceState(state, { type: "verification", category: "test", success: true, timestamp: at(3), sessionId: "s" });
  state = reduceState(state, { type: "turn-stop", timestamp: at(4), sessionId: "s" });
  const previousBestMomentum = state.bestMomentum;
  const previousBestCombo = state.bestCombo;
  assert.equal(state.completion, "verified");
  assert.equal(state.edits, 1);
  assert.deepEqual(state.evidence, ["test"]);

  state = reduceState(state, {
    type: "activity-start", phase: "observe", toolGroup: "prompt", timestamp: at(30), sessionId: "s"
  });
  assert.equal(state.momentum, 1);
  assert.equal(state.combo, 1);
  assert.equal(state.confidence, 0);
  assert.equal(state.risk, 0);
  assert.equal(state.edits, 0);
  assert.equal(state.addedLines, 0);
  assert.equal(state.verifications, 0);
  assert.deepEqual(state.evidence, []);
  assert.equal(state.lastEditAt, null);
  assert.equal(state.lastVerificationAt, null);
  assert.equal(state.bestMomentum, previousBestMomentum);
  assert.equal(state.bestCombo, previousBestCombo);

  state = reduceState(state, { type: "turn-stop", timestamp: at(31), sessionId: "s" });
  assert.equal(state.completion, "no-change");
});

test("abandoned non-terminal activity settles without hiding attention states", () => {
  const working = reduceState(initialState, {
    type: "activity-start", phase: "observe", toolGroup: "prompt", timestamp: at(1), sessionId: "s"
  });
  assert.equal(presentationSnapshot(working, at(300)).phase, "observe");
  assert.equal(presentationSnapshot(working, at(305)).phase, "idle");
  assert.equal(presentationSnapshot(working, at(309)).momentum, 0);

  const waiting = reduceState(working, { type: "permission-request", timestamp: at(2), sessionId: "s" });
  assert.equal(presentationSnapshot(waiting, at(10_000)).phase, "wait");
  assert.equal(presentationSnapshot(waiting, at(10_000)).idle, false);
});

test("unverified edits cannot claim an evidence-backed completion", () => {
  let state = reduceState(initialState, {
    type: "edit", timestamp: at(2), addedLines: 2, removedLines: 0, addedChars: 20
  });
  state = reduceState(state, { type: "turn-stop", timestamp: at(3) });
  assert.equal(state.completion, "unverified");
  assert.equal(state.status, "unverified");
});

test("a turn without edits completes without asking for verification", () => {
  const state = reduceState(initialState, { type: "turn-stop", timestamp: at(2) });
  assert.equal(state.phase, "complete");
  assert.equal(state.completion, "no-change");
  assert.equal(state.currentActivity, "Turn complete");
  assert.equal(state.comboStatus, "idle");
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
  assert.equal(comboDisplayStatus(state, at(5)), "broken");
  assert.equal(comboDisplayStatus(state, at(7)), "idle");
});

test("an expired combo shows LOST briefly and then returns to READY", () => {
  const state = reduceState(initialState, {
    type: "activity-start", phase: "observe", toolGroup: "search", timestamp: at(1), sessionId: "s"
  });
  assert.equal(comboDisplayStatus(state, at(13.5)), "broken");
  assert.equal(comboDisplayStatus(state, at(16.3)), "idle");
});

test("failed edits enter recovery and immediately break the combo", () => {
  let state = reduceState(initialState, {
    type: "activity-start", phase: "act", toolGroup: "change", timestamp: at(1), sessionId: "s"
  });
  state = reduceState(state, { type: "edit-failure", timestamp: at(2), sessionId: "s" });
  assert.equal(state.phase, "recover");
  assert.equal(state.status, "failed");
  assert.equal(state.edits, 0);
  assert.equal(state.combo, 0);
  assert.equal(state.comboStatus, "broken");
  assert.equal(state.comboBreaks, 1);
});

test("stopping while permission is pending cancels and breaks the combo", () => {
  let state = reduceState(initialState, {
    type: "activity-start", phase: "act", toolGroup: "command", timestamp: at(1), sessionId: "s"
  });
  state = reduceState(state, { type: "permission-request", timestamp: at(2), sessionId: "s" });
  state = reduceState(state, { type: "turn-stop", timestamp: at(3), sessionId: "s" });
  assert.equal(state.phase, "complete");
  assert.equal(state.status, "cancelled");
  assert.equal(state.completion, "cancelled");
  assert.equal(state.currentActivity, "Approval was not granted");
  assert.equal(state.combo, 0);
  assert.equal(state.comboStatus, "broken");
  assert.equal(state.comboBreaks, 1);
});

test("work resuming after approval leaves wait without breaking the combo", () => {
  let state = reduceState(initialState, {
    type: "activity-start", phase: "act", toolGroup: "command", timestamp: at(1), sessionId: "s"
  });
  state = reduceState(state, { type: "permission-request", timestamp: at(2), sessionId: "s" });
  assert.equal(state.phase, "wait");
  assert.equal(state.comboStatus, "waiting");

  state = reduceState(state, {
    type: "activity-start", phase: "act", toolGroup: "command", timestamp: at(3), sessionId: "s"
  });
  assert.equal(state.phase, "act");
  assert.equal(state.status, "working");
  assert.equal(state.currentActivity, "Executing a command");
  assert.equal(state.combo, 2);
  assert.equal(state.comboStatus, "holding");
  assert.equal(state.comboBreaks, 0);
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
