import assert from "node:assert/strict";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import { classifySessionSource, sessionSourceFromTranscript, shouldTrackSessionSource } from "../src/session-source.mjs";

test("session transcript metadata distinguishes desktop, CLI, and subagents", () => {
  assert.equal(classifySessionSource('{"payload":{"originator":"codex_work_desktop","source":"vscode"}}'), "desktop");
  assert.equal(classifySessionSource('{"payload":{"originator":"Codex Desktop","source":"exec"}}'), "cli");
  assert.equal(classifySessionSource('{"payload":{"source":{"subagent":{"depth":1}}}}'), "subagent");
  assert.equal(classifySessionSource('{"payload":{}}'), "unknown");
});

test("session source reader fails closed when a transcript is unavailable", async () => {
  const directory = await mkdtemp(path.join(tmpdir(), "codex-power-mode-source-"));
  const transcript = path.join(directory, "rollout.jsonl");
  try {
    await writeFile(transcript, '{"type":"session_meta","payload":{"source":"vscode"}}\n');
    assert.equal(await sessionSourceFromTranscript(transcript), "desktop");
    assert.equal(await sessionSourceFromTranscript(path.join(directory, "missing.jsonl")), "unknown");
    assert.equal(await sessionSourceFromTranscript(null), "unknown");
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test("Power Mode only tracks Codex desktop sessions", () => {
  assert.equal(shouldTrackSessionSource("desktop"), true);
  assert.equal(shouldTrackSessionSource("cli"), false);
  assert.equal(shouldTrackSessionSource("subagent"), false);
  assert.equal(shouldTrackSessionSource("unknown"), false);
});
