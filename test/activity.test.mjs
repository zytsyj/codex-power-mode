import assert from "node:assert/strict";
import test from "node:test";
import { createActivityTracker } from "../src/activity.mjs";

test("activity tracker distinguishes real Codex events from demos", () => {
  const tracker = createActivityTracker();

  tracker.record({ type: "edit", timestamp: "2026-07-21T00:00:00.000Z", sessionId: "demo" });
  tracker.record({ type: "turn-stop", timestamp: "2026-07-21T00:01:00.000Z", sessionId: "session-1" });

  assert.deepEqual(tracker.snapshot(), {
    eventsReceived: 2,
    realEventsReceived: 1,
    lastEvent: {
      type: "turn-stop",
      timestamp: "2026-07-21T00:01:00.000Z",
      sessionId: "session-1"
    },
    lastRealEvent: {
      type: "turn-stop",
      timestamp: "2026-07-21T00:01:00.000Z",
      sessionId: "session-1"
    }
  });
});

test("activity tracker starts empty and ignores missing session ids as real activity", () => {
  const tracker = createActivityTracker();
  assert.deepEqual(tracker.snapshot(), {
    eventsReceived: 0,
    realEventsReceived: 0,
    lastEvent: null,
    lastRealEvent: null
  });

  tracker.record({ type: "connected" });
  assert.equal(tracker.snapshot().realEventsReceived, 0);
  assert.equal(tracker.snapshot().lastRealEvent, null);
});
