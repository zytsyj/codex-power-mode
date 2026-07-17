import test from "node:test";
import assert from "node:assert/strict";
import { initialState, reduceState } from "../src/state.mjs";

const at = (seconds) => new Date(seconds * 1_000).toISOString();

test("edits build combo and invalidate earlier verification", () => {
  const state = reduceState(initialState, {
    type: "edit",
    timestamp: at(2),
    addedLines: 5,
    removedLines: 1,
    addedChars: 100,
    sessionId: "s"
  });
  assert.ok(state.combo > 0);
  assert.equal(state.mode, "combo");
  assert.equal(state.lastVerificationPassed, false);
});

test("failed verification resets combo", () => {
  const state = reduceState({ ...initialState, combo: 20 }, {
    type: "verification",
    category: "test",
    success: false,
    timestamp: at(3)
  });
  assert.equal(state.combo, 0);
  assert.equal(state.mode, "danger");
});

test("turn reaches victory only after post-edit verification", () => {
  let state = reduceState(initialState, {
    type: "edit",
    timestamp: at(2),
    addedLines: 2,
    removedLines: 0,
    addedChars: 20
  });
  state = reduceState(state, {
    type: "verification",
    category: "test",
    success: true,
    timestamp: at(3)
  });
  state = reduceState(state, { type: "turn-stop", timestamp: at(4) });
  assert.equal(state.mode, "victory");
});

test("unverified edits cannot claim victory", () => {
  let state = reduceState(initialState, {
    type: "edit",
    timestamp: at(2),
    addedLines: 2,
    removedLines: 0,
    addedChars: 20
  });
  state = reduceState(state, { type: "turn-stop", timestamp: at(3) });
  assert.equal(state.mode, "unverified");
});
