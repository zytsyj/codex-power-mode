import assert from "node:assert/strict";
import test from "node:test";
import {
  createInteractionSession,
  interactionChecks,
  recordInteractionResult,
  restoreInteractionSession,
  summarizeInteractionSession
} from "../src/interaction-acceptance.mjs";

const configuration = {
  schemaVersion: 1,
  preset: "arcade",
  edge: "top-right",
  scale: 1.3,
  reducedMotion: false,
  inactiveBehavior: "follow",
  autoHideDelay: 2,
  enabled: true,
  idleBehavior: "hide",
  language: "auto",
  activitySource: "mix",
  effectIntensity: "normal",
  showCombo: true,
  typingCombo: true,
  cursorEffect: "spark",
  positionX: null,
  positionY: null,
  endpoint: "http://127.0.0.1:4737/api/stream"
};

test("interaction RC starts with a privacy-safe pending checklist and normalized baseline", () => {
  const session = createInteractionSession(configuration, "0.8.0-test", new Date("2026-07-22T18:00:00Z"));
  const summary = summarizeInteractionSession(session);

  assert.equal(interactionChecks.length, 15);
  assert.equal(summary.counts.pending, 15);
  assert.equal(summary.counts.passed, 0);
  assert.deepEqual(session.baselineConfiguration, configuration);
  assert.equal(Object.hasOwn(session, "notes"), false);
  assert.equal(Object.hasOwn(session, "taskId"), false);
  assert.equal(Object.hasOwn(session, "sessionId"), false);
});

test("interaction RC accepts only explicit predefined results", () => {
  const session = createInteractionSession(configuration, "0.8.0-test");
  const recorded = recordInteractionResult(session, "cursor-spark", "passed");
  assert.equal(recorded.results["cursor-spark"], "passed");
  assert.equal(session.results["cursor-spark"], "pending");
  assert.throws(() => recordInteractionResult(session, "cursor-spark", "pending"));
  assert.throws(() => recordInteractionResult(session, "unknown", "passed"));
});

test("interaction RC refuses a non-loopback checkpoint and marks restoration explicitly", () => {
  assert.throws(() => createInteractionSession({ ...configuration, endpoint: "https://example.com/api/stream" }, "test"));
  const session = createInteractionSession(configuration, "test");
  const restored = restoreInteractionSession(session, new Date("2026-07-22T18:05:00Z"));
  assert.equal(restored.status, "restored");
  assert.equal(restored.restoredAt, "2026-07-22T18:05:00.000Z");
  assert.throws(() => restoreInteractionSession({
    ...session,
    baselineConfiguration: { ...session.baselineConfiguration, endpoint: "https://example.com/api/stream" }
  }));
});
