import assert from "node:assert/strict";
import test from "node:test";
import { createSessionArbiter } from "../src/session-arbiter.mjs";

const event = (sessionId, type, timestamp) => ({ sessionId, type, timestamp: new Date(timestamp).toISOString() });

test("a concurrent session cannot replace an active HUD owner", () => {
  const arbiter = createSessionArbiter({}, { leaseMs: 30_000, now: () => 0 });

  assert.deepEqual(arbiter.consider(event("desktop", "activity-start", 1_000)), { displayed: true, switched: true });
  assert.deepEqual(arbiter.consider(event("cli", "activity-start", 2_000)), { displayed: false, switched: false });
  assert.deepEqual(arbiter.consider(event("desktop", "edit", 3_000)), { displayed: true, switched: false });
  assert.deepEqual(arbiter.snapshot(), {
    activeSessionId: "desktop",
    lastSwitchAt: 1_000,
    suppressedEvents: 1,
    leaseMs: 30_000
  });
});

test("ownership passes after the active turn stops", () => {
  const arbiter = createSessionArbiter({}, { leaseMs: 30_000, now: () => 0 });
  arbiter.consider(event("desktop", "activity-start", 1_000));
  arbiter.consider(event("desktop", "turn-stop", 2_000));

  assert.deepEqual(arbiter.consider(event("cli", "activity-start", 2_100)), { displayed: true, switched: true });
  assert.equal(arbiter.snapshot().activeSessionId, "cli");
});

test("a stale owner cannot permanently block a newer conversation", () => {
  const arbiter = createSessionArbiter({}, { leaseMs: 30_000, now: () => 0 });
  arbiter.consider(event("desktop", "activity-start", 1_000));

  assert.deepEqual(arbiter.consider(event("cli", "activity-start", 31_000)), { displayed: true, switched: true });
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
  arbiter.consider(event("desktop", "activity-start", 1_000));

  assert.deepEqual(arbiter.consider(event("demo", "edit", 2_000)), { displayed: true, switched: false });
  assert.equal(arbiter.snapshot().activeSessionId, "desktop");
});

test("late events from the active session cannot roll the HUD backward", () => {
  const arbiter = createSessionArbiter({}, { now: () => 0 });
  arbiter.consider(event("desktop", "edit", 3_000));

  assert.deepEqual(arbiter.consider(event("desktop", "activity-start", 2_000)), { displayed: false, switched: false });
  assert.equal(arbiter.snapshot().activeSessionId, "desktop");
  assert.equal(arbiter.snapshot().suppressedEvents, 1);
});
