import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";

const root = path.resolve(import.meta.dirname, "..");

function runHook(input, dataDir) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [path.join(root, "hooks/power-mode-hook.mjs")], {
      cwd: root,
      env: { ...process.env, CODEX_POWER_MODE_DATA: dataDir, CODEX_POWER_MODE_PORT: "1" },
      stdio: ["pipe", "pipe", "pipe"]
    });
    let stderr = "";
    child.stderr.on("data", (chunk) => { stderr += chunk; });
    child.once("error", reject);
    child.once("exit", (code) => code === 0 ? resolve() : reject(new Error(stderr || `Hook exited ${code}`)));
    child.stdin.end(JSON.stringify(input));
  });
}

test("hook records Codex desktop activity and ignores CLI activity", async () => {
  const directory = await mkdtemp(path.join(tmpdir(), "codex-power-mode-hook-"));
  const dataDir = path.join(directory, "data");
  const desktopTranscript = path.join(directory, "desktop.jsonl");
  const cliTranscript = path.join(directory, "cli.jsonl");
  try {
    await writeFile(desktopTranscript, '{"type":"session_meta","payload":{"originator":"codex_work_desktop","source":"vscode"}}\n');
    await writeFile(cliTranscript, '{"type":"session_meta","payload":{"source":"exec"}}\n');

    await runHook({
      hook_event_name: "PreToolUse",
      session_id: "cli-session",
      transcript_path: cliTranscript,
      tool_name: "Read"
    }, dataDir);
    await assert.rejects(readFile(path.join(dataDir, "events.ndjson"), "utf8"), { code: "ENOENT" });

    await runHook({
      hook_event_name: "UserPromptSubmit",
      session_id: "desktop-session",
      turn_id: "turn-1",
      transcript_path: desktopTranscript,
      prompt: "private prompt content"
    }, dataDir);
    await runHook({
      hook_event_name: "PreToolUse",
      session_id: "desktop-session",
      transcript_path: desktopTranscript,
      tool_name: "Read"
    }, dataDir);
    const events = (await readFile(path.join(dataDir, "events.ndjson"), "utf8")).trim().split("\n").map(JSON.parse);
    assert.equal(events.length, 2);
    assert.equal(events[0].sessionId, "desktop-session");
    assert.equal(events[0].sessionSource, "desktop");
    assert.equal(events[0].toolGroup, "prompt");
    assert.equal(JSON.stringify(events[0]).includes("private prompt content"), false);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});
