import assert from "node:assert/strict";
import test from "node:test";
import { connectionDiagnostics } from "../src/diagnostics.mjs";

const health = (lastRealEvent = null, clients = 1) => ({
  clients,
  activity: { lastRealEvent },
  session: { activeSessionId: "session-a" }
});

test("connection diagnostics distinguish waiting, receiving, idle, and service-only states", () => {
  const now = Date.parse("2026-07-21T14:30:00.000Z");
  const state = { sessionId: "session-a" };

  assert.equal(connectionDiagnostics({ health: health(), nativePid: 10, state, now }).status, "waiting-for-task");

  const recent = connectionDiagnostics({
    health: health({ type: "edit", timestamp: "2026-07-21T14:29:00.000Z", sessionId: "session-a" }),
    nativePid: 10,
    state,
    now
  });
  assert.equal(recent.status, "receiving");
  assert.equal(recent.lastRealEventAgeMs, 60_000);
  assert.equal(recent.sessionMatchesLastEvent, true);

  const idle = connectionDiagnostics({
    health: health({ type: "turn-stop", timestamp: "2026-07-21T14:00:00.000Z", sessionId: "session-b" }),
    nativePid: 10,
    state,
    now
  });
  assert.equal(idle.status, "idle");
  assert.equal(idle.sessionMatchesLastEvent, false);

  assert.equal(connectionDiagnostics({ health: health(null, 0), nativePid: null, state, now }).status, "service-only");
  assert.equal(connectionDiagnostics({ health: null, nativePid: null, state, now }).status, "offline");
});
