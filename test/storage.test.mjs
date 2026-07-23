import test from "node:test";
import assert from "node:assert/strict";
import { access, mkdir, mkdtemp, rm, utimes, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import {
  readSessionState,
  readState,
  recordEventResult,
  recordMixedEventResult,
  recordSessionEventResult,
  writeStateSnapshot
} from "../src/storage.mjs";
import { presentationSnapshot } from "../src/state.mjs";

const eventAt = (milliseconds) => ({
  type: "activity-start",
  phase: "observe",
  toolGroup: "search",
  timestamp: new Date(milliseconds).toISOString(),
  sessionId: "coalesce-test"
});

test("storage records at most one identical observe event per throttle window", async () => {
  const directory = await mkdtemp(path.join(tmpdir(), "codex-power-mode-"));
  try {
    const first = await recordEventResult(directory, eventAt(1_000), { coalesceWindowMs: 900 });
    const duplicate = await recordEventResult(directory, eventAt(1_500), { coalesceWindowMs: 900 });
    const later = await recordEventResult(directory, eventAt(2_000), { coalesceWindowMs: 900 });
    assert.equal(first.recorded, true);
    assert.equal(duplicate.recorded, false);
    assert.equal(later.recorded, true);
    assert.equal(later.state.steps, 2);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test("storage does not inherit the legacy ever-increasing combo score", async () => {
  const directory = await mkdtemp(path.join(tmpdir(), "codex-power-mode-"));
  try {
    await writeFile(path.join(directory, "state.json"), JSON.stringify({
      phase: "complete", combo: 460, bestCombo: 460, score: 460, mode: "victory"
    }));
    const state = await readState(directory);
    assert.equal(state.combo, 0);
    assert.equal(state.bestCombo, 0);
    assert.equal(state.comboStatus, "idle");
    assert.equal("score" in state, false);
    assert.equal("mode" in state, false);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test("storage recovers the latest real session from a legacy persisted demo", async () => {
  const directory = await mkdtemp(path.join(tmpdir(), "codex-power-mode-demo-recovery-"));
  try {
    await mkdir(path.join(directory, "sessions"));
    await writeFile(path.join(directory, "state.json"), JSON.stringify({
      sessionId: "demo", momentum: 88, bestMomentum: 99, lastActivityAt: new Date(3_000).toISOString()
    }));
    await writeFile(path.join(directory, "sessions", "older.json"), JSON.stringify({
      sessionId: "older", sessionSource: "desktop", momentum: 5, bestMomentum: 12,
      lastActivityAt: new Date(1_000).toISOString()
    }));
    await writeFile(path.join(directory, "sessions", "latest.json"), JSON.stringify({
      sessionId: "latest", sessionSource: "desktop", momentum: 7, bestMomentum: 22,
      lastActivityAt: new Date(2_000).toISOString()
    }));

    const state = await readState(directory);
    assert.equal(state.sessionId, "latest");
    assert.equal(state.momentum, 7);
    assert.equal(state.bestMomentum, 22);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test("a streamed state snapshot survives reconnect without duplicating event history", async () => {
  const directory = await mkdtemp(path.join(tmpdir(), "codex-power-mode-"));
  try {
    await writeStateSnapshot(directory, {
      phase: "wait",
      status: "needs-attention",
      currentActivity: "Waiting for your approval",
      combo: 3,
      comboStatus: "waiting"
    });
    const state = await readState(directory);
    assert.equal(state.phase, "wait");
    assert.equal(state.status, "needs-attention");
    assert.equal(state.combo, 3);
    assert.equal(state.comboStatus, "waiting");
    await assert.rejects(access(path.join(directory, "events.ndjson")), { code: "ENOENT" });
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test("storage recovers a stale lock left by a terminated hook process", async () => {
  const directory = await mkdtemp(path.join(tmpdir(), "codex-power-mode-"));
  const lockPath = path.join(directory, "state.lock");
  try {
    await writeFile(lockPath, JSON.stringify({ pid: 2_147_483_647, acquiredAt: "2020-01-01T00:00:00.000Z" }));
    const old = new Date(Date.now() - 60_000);
    await utimes(lockPath, old, old);

    const result = await recordEventResult(directory, eventAt(1_000));
    assert.equal(result.recorded, true);
    assert.equal(result.state.steps, 1);
    await assert.rejects(access(lockPath), { code: "ENOENT" });
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test("hook sessions keep independent momentum and combo state", async () => {
  const directory = await mkdtemp(path.join(tmpdir(), "codex-power-mode-sessions-"));
  try {
    await recordSessionEventResult(directory, { ...eventAt(1_000), sessionId: "thread-a" });
    await recordSessionEventResult(directory, { ...eventAt(1_200), sessionId: "thread-a" });
    await recordSessionEventResult(directory, { ...eventAt(1_300), sessionId: "thread-b" });

    const [threadA, threadB, displayed] = await Promise.all([
      readSessionState(directory, "thread-a"),
      readSessionState(directory, "thread-b"),
      readState(directory)
    ]);
    assert.equal(threadA.steps, 2);
    assert.equal(threadA.combo, 2);
    assert.equal(threadB.steps, 1);
    assert.equal(threadB.combo, 1);
    assert.equal(displayed.steps, 0);
    assert.equal(displayed.combo, 0);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test("stored Energy gain setting applies to the very next Hook event", async () => {
  const directory = await mkdtemp(path.join(tmpdir(), "codex-power-mode-energy-gain-"));
  try {
    const nativeDirectory = path.join(directory, "native");
    await mkdir(nativeDirectory, { recursive: true });
    await writeFile(path.join(nativeDirectory, "overlay-config.json"), JSON.stringify({ energyGainMultiplier: 0.55 }));
    const slow = await recordSessionEventResult(directory, { ...eventAt(1_000), sessionId: "slow" });
    assert.equal(slow.state.momentum, 8);

    await writeFile(path.join(nativeDirectory, "overlay-config.json"), JSON.stringify({ energyGainMultiplier: 1.1 }));
    const turbo = await recordSessionEventResult(directory, { ...eventAt(2_000), sessionId: "turbo" });
    assert.equal(turbo.state.momentum, 15);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test("mix storage shares energy and Combo without letting one parallel stop reset the pool", async () => {
  const directory = await mkdtemp(path.join(tmpdir(), "codex-power-mode-mix-"));
  try {
    let result = await recordMixedEventResult(directory, { ...eventAt(1_000), sessionId: "thread-a" });
    result = await recordMixedEventResult(directory, { ...eventAt(2_000), sessionId: "thread-b" });
    assert.equal(result.state.sessionId, "mix");
    assert.equal(result.state.momentum, 20);
    assert.equal(result.state.combo, 2);
    assert.equal(result.state.mixedConversationCount, 2);

    result = await recordMixedEventResult(directory, {
      type: "turn-stop", timestamp: new Date(3_000).toISOString(), sessionId: "thread-a",
      mixCompletion: "no-change"
    });
    assert.notEqual(result.state.phase, "complete");
    assert.equal(result.state.combo, 2);
    assert.equal(result.state.mixedConversationCount, 1);
    assert.equal(result.state.mixedLastCompletion, "no-change");

    result = await recordMixedEventResult(directory, {
      type: "turn-stop", timestamp: new Date(4_000).toISOString(), sessionId: "thread-b",
      mixCompletion: "no-change"
    });
    assert.equal(result.state.phase, "complete");
    assert.equal(result.state.mixedConversationCount, 0);
    const idle = presentationSnapshot(result.state, new Date(10_000).toISOString());
    assert.equal(idle.phase, "idle");
    assert.ok(idle.momentum > 0 && idle.momentum < result.state.momentum);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});
