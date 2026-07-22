import assert from "node:assert/strict";
import test from "node:test";
import { createSessionArbiter } from "../src/session-arbiter.mjs";

const event = (sessionId, type, timestamp, sessionSource = "unknown") => ({ sessionId, type, sessionSource, timestamp: new Date(timestamp).toISOString() });

test("a concurrent session cannot replace an active HUD owner", () => {
  const arbiter = createSessionArbiter({}, { leaseMs: 30_000, now: () => 0 });

  assert.deepEqual(arbiter.consider(event("conversation-a", "activity-start", 1_000)), { displayed: true, switched: true });
  assert.deepEqual(arbiter.consider(event("conversation-b", "activity-start", 2_000)), { displayed: false, switched: false });
  assert.deepEqual(arbiter.consider(event("conversation-a", "edit", 3_000)), { displayed: true, switched: false });
  assert.deepEqual(arbiter.snapshot(), {
    activeSessionId: "conversation-a",
    activeSessionSource: "unknown",
    lastSwitchAt: 1_000,
    suppressedEvents: 1,
    leaseMs: 30_000,
    mixedSessions: 0
  });
});

test("ownership passes after the active turn stops", () => {
  const arbiter = createSessionArbiter({}, { leaseMs: 30_000, now: () => 0 });
  arbiter.consider(event("conversation-a", "activity-start", 1_000));
  arbiter.consider(event("conversation-a", "turn-stop", 2_000));

  assert.deepEqual(arbiter.consider(event("conversation-b", "activity-start", 2_100)), { displayed: true, switched: true });
  assert.equal(arbiter.snapshot().activeSessionId, "conversation-b");
});

test("a stale owner cannot permanently block a newer conversation", () => {
  const arbiter = createSessionArbiter({}, { leaseMs: 30_000, now: () => 0 });
  arbiter.consider(event("conversation-a", "activity-start", 1_000));

  assert.deepEqual(arbiter.consider(event("conversation-b", "activity-start", 31_000)), { displayed: true, switched: true });
});

test("a completed persisted session releases ownership after restart", () => {
  const arbiter = createSessionArbiter({
    sessionId: "previous",
    status: "complete",
    lastActivityAt: new Date(1_000).toISOString()
  }, { now: () => 2_000 });

  assert.deepEqual(arbiter.consider(event("next", "activity-start", 2_000)), { displayed: true, switched: true });
});

test("demo events display without stealing real-session ownership", () => {
  const arbiter = createSessionArbiter({}, { now: () => 0 });
  arbiter.consider(event("conversation-a", "activity-start", 1_000));

  assert.deepEqual(arbiter.consider(event("demo", "edit", 2_000)), { displayed: true, switched: false });
  assert.equal(arbiter.snapshot().activeSessionId, "conversation-a");
});

test("late events from the active session cannot roll the HUD backward", () => {
  const arbiter = createSessionArbiter({}, { now: () => 0 });
  arbiter.consider(event("conversation-a", "edit", 3_000));

  assert.deepEqual(arbiter.consider(event("conversation-a", "activity-start", 2_000)), { displayed: false, switched: false });
  assert.equal(arbiter.snapshot().activeSessionId, "conversation-a");
  assert.equal(arbiter.snapshot().suppressedEvents, 1);
});

test("global mode follows the latest session while keeping stale events out", () => {
  const arbiter = createSessionArbiter({}, { now: () => 0 });
  arbiter.consider(event("conversation-a", "activity-start", 1_000));

  assert.deepEqual(
    arbiter.consider(event("conversation-b", "activity-start", 2_000), { mode: "global" }),
    { displayed: true, switched: true }
  );
  assert.deepEqual(
    arbiter.consider(event("conversation-a", "edit", 1_500), { mode: "global" }),
    { displayed: false, switched: false }
  );
  assert.equal(arbiter.snapshot().activeSessionId, "conversation-b");
});

test("mix mode accepts every conversation without switching the shared HUD", () => {
  const arbiter = createSessionArbiter({}, { now: () => 0 });
  assert.deepEqual(
    arbiter.consider(event("conversation-a", "activity-start", 1_000), { mode: "mix" }),
    { displayed: true, switched: false, mixed: true }
  );
  assert.deepEqual(
    arbiter.consider(event("conversation-b", "edit", 2_000), { mode: "mix" }),
    { displayed: true, switched: false, mixed: true }
  );
  assert.equal(arbiter.snapshot().activeSessionId, "mix");
  assert.equal(arbiter.snapshot().mixedSessions, 2);
});
