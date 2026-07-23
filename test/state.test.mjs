import test from "node:test";
import assert from "node:assert/strict";
import { COMBO_DECAY_MS, ENERGY_GAIN_MULTIPLIER, MOMENTUM_RETURN_MS, comboDisplayStatus, comboProgress, comboStage, energyAt, energyLevel, energyStage, initialState, normalizeEnergyGainMultiplier, presentationSnapshot, reduceState, shouldCoalesceActivity, typingChargeForCombo } from "../src/state.mjs";

const at = (seconds) => new Date(seconds * 1_000).toISOString();

test("activity events represent Codex states without rewarding code volume", () => {
  const state = reduceState(initialState, {
    type: "activity-start", phase: "observe", toolGroup: "search", timestamp: at(1), sessionId: "s"
  });
  assert.equal(state.phase, "observe");
  assert.equal(state.momentum, 10);
  assert.equal(state.currentActivity, "Searching the workspace");
});

test("prompt submission immediately enters understanding", () => {
  const state = reduceState(initialState, {
    type: "activity-start", phase: "observe", toolGroup: "prompt", timestamp: at(1), sessionId: "s"
  });
  assert.equal(state.phase, "observe");
  assert.equal(state.currentActivity, "Understanding request");
  assert.equal(state.momentum, 10);
  assert.equal(state.combo, 1);
});

test("energy stage progress refills inside every tier", () => {
  assert.deepEqual(energyStage(199), { name: "awakening", lower: 1, upper: 199, value: 199, progress: 1 });
  assert.equal(energyStage(200).name, "charging");
  assert.equal(energyStage(200).progress, 0);
  assert.equal(energyStage(449).progress, 1);
  assert.equal(energyStage(450).name, "driving");
  assert.equal(energyStage(450).progress, 0);
  assert.equal(energyStage(700).name, "critical");
  assert.equal(energyStage(998).progress, 1);
  assert.equal(energyStage(999).name, "verified-peak");
  assert.equal(energyStage(999).progress, 1);
});

test("typing Combo injects a bounded tiered charge without advancing agent Combo", () => {
  assert.equal(ENERGY_GAIN_MULTIPLIER, 0.72);
  assert.deepEqual([1, 5, 10, 20, 40, 200].map((combo) => typingChargeForCombo(combo)), [4, 12, 23, 40, 65, 65]);
  const prior = { ...initialState, momentum: 95, combo: 3, sessionId: "s" };
  const state = reduceState(prior, {
    type: "input-charge", inputCombo: 10, timestamp: at(2), sessionId: "s", sessionSource: "desktop"
  });
  assert.equal(state.momentum, 118);
  assert.equal(state.combo, 3);
  assert.equal(state.phase, "observe");
  assert.equal(state.currentActivity, "Understanding request");
});

test("Energy gain presets change the next event without changing tier boundaries", () => {
  const event = { type: "edit", timestamp: at(2), addedLines: 2, removedLines: 0, sessionId: "s" };
  assert.deepEqual(
    [0.3, 0.4, 0.5, 0.6, 0.72, 0.85, 1, 1.15, 1.3, 1.5]
      .map((energyGainMultiplier) => reduceState(initialState, event, { energyGainMultiplier }).momentum),
    [26, 34, 43, 51, 61, 72, 85, 98, 111, 128]
  );
  assert.equal(normalizeEnergyGainMultiplier(0.55), 0.5);
  assert.equal(normalizeEnergyGainMultiplier(0.9), 0.85);
  assert.equal(normalizeEnergyGainMultiplier(1.1), 1.15);
  assert.equal(normalizeEnergyGainMultiplier(0.73), 0.72);
  assert.equal(energyStage(200).name, "charging");
});

test("typing charge cannot claim the evidence-backed peak", () => {
  const state = reduceState({ ...initialState, momentum: 980, sessionId: "s" }, {
    type: "input-charge", inputCombo: 200, timestamp: at(2), sessionId: "s", sessionSource: "desktop"
  });
  assert.equal(state.momentum, 998);
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
  assert.equal(state.momentum, 0);
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
  assert.equal(state.comboStatus, "reward");
  assert.equal(state.verificationReward, "confirmation");
  assert.equal(comboStage(state, at(4)), "confirmed");
  assert.equal(comboProgress(state, at(4)), 1);
});

test("verification rewards distinguish evidence, records, and standalone confirmation", () => {
  let state = reduceState({ ...initialState, bestMomentum: 500, bestCombo: 12 }, {
    type: "edit", timestamp: at(1), addedLines: 2, removedLines: 0, sessionId: "s"
  });
  state = reduceState(state, { type: "verification", category: "test", success: true, timestamp: at(2), sessionId: "s" });
  assert.equal(state.verificationReward, "evidence");
  assert.equal(comboStage(state, at(2.5)), "reward");

  let record = reduceState(initialState, {
    type: "edit", timestamp: at(1), addedLines: 2, removedLines: 0, sessionId: "s"
  });
  record = reduceState(record, { type: "verification", category: "build", success: true, timestamp: at(2), sessionId: "s" });
  assert.equal(record.verificationReward, "record");
  assert.equal(record.verificationRewardAt, at(2));
  assert.equal(comboStage(record, at(2.5)), "record");
});

test("energy levels span awakening through a verified 999 peak", () => {
  assert.equal(energyLevel(0), "idle");
  assert.equal(energyLevel(1), "awakening");
  assert.equal(energyLevel(200), "charging");
  assert.equal(energyLevel(450), "driving");
  assert.equal(energyLevel(700), "critical");
  assert.equal(energyLevel(998), "critical");
  assert.equal(energyLevel(999), "verified-peak");
});

test("energy has a grace period, decays by real elapsed time, and materializes before the next event", () => {
  const charged = { ...initialState, momentum: 600, energyUpdatedAt: at(1), lastActivityAt: at(1), sessionId: "s" };
  assert.equal(energyAt(charged, at(21)), 600);
  assert.equal(energyAt(charged, at(66)), 300);
  assert.equal(energyAt(charged, at(111)), 0);
  const resumed = reduceState(charged, {
    type: "activity-start", phase: "observe", toolGroup: "search", timestamp: at(66), sessionId: "s"
  });
  assert.equal(resumed.momentum, 310);
});

test("only an evidence-backed edited completion reaches the 999 peak", () => {
  let verified = reduceState(initialState, { type: "edit", timestamp: at(1), addedLines: 2, removedLines: 0, sessionId: "s" });
  verified = reduceState(verified, { type: "verification", category: "test", success: true, timestamp: at(2), sessionId: "s" });
  verified = reduceState(verified, { type: "turn-stop", timestamp: at(3), sessionId: "s" });
  assert.equal(verified.momentum, 999);

  let unverified = reduceState(initialState, { type: "edit", timestamp: at(1), addedLines: 2, removedLines: 0, sessionId: "s" });
  unverified = reduceState(unverified, { type: "turn-stop", timestamp: at(3), sessionId: "s" });
  assert.ok(unverified.momentum < 999);
});

test("combo stages span ignition through extreme and critical timing", () => {
  const base = {
    ...initialState,
    combo: 2,
    comboStatus: "decaying",
    comboLastAt: at(1),
    comboHoldUntil: at(1),
    comboExpiresAt: at(13)
  };
  assert.equal(comboStage(base, at(2)), "ignition");
  assert.equal(comboStage({ ...base, combo: 5 }, at(2)), "linked");
  assert.equal(comboStage({ ...base, combo: 10 }, at(2)), "accelerated");
  assert.equal(comboStage({ ...base, combo: 20 }, at(2)), "heated");
  assert.equal(comboStage({ ...base, combo: 40 }, at(2)), "extreme");
  assert.equal(comboStage({ ...base, combo: 7 }, at(11)), "critical");
  assert.equal(comboStage({ ...base, combo: 7 }, at(13.5)), "lost");
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

test("a completed turn becomes idle after feedback and then slowly returns momentum to zero", () => {
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
  const stillReturning = presentationSnapshot(state, at(40));
  assert.equal(stillReturning.phase, "idle");
  assert.ok(stillReturning.momentum > 0);
  const settled = presentationSnapshot(state, at(70));
  assert.equal(settled.momentum, 0);
  assert.equal(settled.combo, 0);
  assert.equal(settled.comboStatus, "idle");
  assert.equal(settled.comboExpiresAt, null);
  assert.ok(state.combo > 0);
  assert.equal(settled.settled, true);
  assert.equal(state.bestMomentum, settled.bestMomentum);
  assert.equal(MOMENTUM_RETURN_MS, 45_000);
});

test("new work cancels the idle countdown", () => {
  let state = reduceState(initialState, { type: "turn-stop", timestamp: at(2), sessionId: "s" });
  state = reduceState(state, {
    type: "activity-start", phase: "observe", toolGroup: "search", timestamp: at(3), sessionId: "s"
  });
  assert.equal(state.turnStoppedAt, null);
  assert.equal(presentationSnapshot(state, at(30)).phase, "observe");
  assert.equal(state.momentum, 10);
  assert.equal(state.combo, 1);
});

test("a new turn carries decayed energy while resetting evidence, risk, and edit scope", () => {
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
  assert.equal(state.momentum, 942);
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
  assert.equal(presentationSnapshot(working, at(350)).momentum, 0);

  const waiting = reduceState(working, { type: "permission-request", timestamp: at(2), sessionId: "s" });
  assert.equal(presentationSnapshot(waiting, at(10_000)).phase, "wait");
  assert.equal(presentationSnapshot(waiting, at(10_000)).idle, false);
});

test("failed recovery remains visible briefly and then safely returns to idle", () => {
  const recovery = reduceState(initialState, {
    type: "verification", category: "test", success: false, timestamp: at(2), sessionId: "s"
  });
  assert.equal(recovery.lastFailureAt, at(2));
  assert.equal(presentationSnapshot(recovery, at(19)).phase, "recover");
  const returning = presentationSnapshot(recovery, at(21));
  assert.equal(returning.phase, "idle");
  assert.equal(returning.status, "ready");
  assert.equal(presentationSnapshot(recovery, at(25)).settled, true);
});

test("legacy failed recovery can settle from its verification timestamp", () => {
  const recovery = {
    ...initialState,
    phase: "recover",
    status: "failed",
    momentum: 12,
    lastFailureAt: null,
    lastVerificationAt: at(2)
  };
  assert.equal(presentationSnapshot(recovery, at(25)).phase, "idle");
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
  assert.equal(COMBO_DECAY_MS, 14_000);
  assert.ok(Math.abs(comboProgress(state, at(18)) - (8 / 14)) < 1e-9);
  assert.equal(comboProgress(state, at(26)), 0);
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
  assert.equal(state.comboRelinkedAt, at(20));
  assert.equal(comboStage(state, at(20.5)), "relinked");
  assert.equal(comboStage(state, at(22)), "ignition");
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
  assert.equal(comboDisplayStatus(state, at(15.5)), "broken");
  assert.equal(comboDisplayStatus(state, at(18.3)), "idle");
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
  assert.equal(state.comboRelinkedAt, null);

  state = reduceState(state, {
    type: "activity-start", phase: "observe", timestamp: at(4), sessionId: "s2"
  });
  assert.equal(state.combo, 1);
  assert.equal(state.comboBreaks, 0);
  assert.equal(state.comboRelinkedAt, null);
});
