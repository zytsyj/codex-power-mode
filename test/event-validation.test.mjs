import assert from "node:assert/strict";
import test from "node:test";
import { validateIncomingEvent } from "../src/event-validation.mjs";

const valid = {
  type: "activity-start",
  id: "event-1",
  timestamp: new Date().toISOString(),
  sessionId: "session-1",
  sessionSource: "desktop",
  phase: "observe"
};

test("event validation accepts reduced lifecycle events", () => {
  assert.equal(validateIncomingEvent(valid), null);
  assert.equal(validateIncomingEvent({ ...valid, type: "edit", addedLines: 2, removedLines: 1 }), null);
  assert.equal(validateIncomingEvent({ ...valid, type: "input-charge", inputCombo: 10 }), null);
});

test("event validation rejects sensitive and malformed input", () => {
  assert.match(validateIncomingEvent({ ...valid, prompt: "secret" }), /Sensitive field/);
  assert.match(validateIncomingEvent({ ...valid, type: "unknown" }), /Unsupported/);
  assert.match(validateIncomingEvent({ ...valid, timestamp: "not-a-date" }), /timestamp/);
  assert.match(validateIncomingEvent({ ...valid, addedLines: -1 }), /addedLines/);
  assert.match(validateIncomingEvent({ ...valid, preview: true }), /demo session/);
  assert.match(validateIncomingEvent({ ...valid, type: "input-charge" }), /inputCombo/);
  assert.match(validateIncomingEvent({ ...valid, type: "input-charge", inputCombo: 201 }), /inputCombo/);
});
