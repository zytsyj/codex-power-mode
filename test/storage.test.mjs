import test from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { readState, recordEventResult } from "../src/storage.mjs";

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
