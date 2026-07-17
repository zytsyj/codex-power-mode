#!/usr/bin/env node
import { spawn } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { recordEvent, readState } from "../src/storage.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const dataDir = path.resolve(process.env.CODEX_POWER_MODE_DATA || path.join(root, ".power-mode"));
const command = process.argv[2] || "start";
const endpoint = "http://127.0.0.1:4737";

async function isRunning() {
  try {
    return (await fetch(`${endpoint}/api/health`, { signal: AbortSignal.timeout(250) })).ok;
  } catch {
    return false;
  }
}

async function start() {
  if (!(await isRunning())) {
    const child = spawn(process.execPath, [path.join(root, "scripts/server.mjs"), "--data-dir", dataDir], {
      cwd: root,
      detached: true,
      stdio: "ignore",
      env: { ...process.env, CODEX_POWER_MODE_DATA: dataDir }
    });
    child.unref();
    for (let attempt = 0; attempt < 30 && !(await isRunning()); attempt += 1) {
      await new Promise((resolve) => setTimeout(resolve, 50));
    }
  }
  if (process.argv.includes("--open")) {
    const opener = process.platform === "darwin" ? ["open", [endpoint]] :
      process.platform === "win32" ? ["cmd", ["/c", "start", endpoint]] : ["xdg-open", [endpoint]];
    spawn(opener[0], opener[1], { detached: true, stdio: "ignore" }).unref();
  }
  process.stdout.write(`${endpoint}\n`);
}

async function emit(event) {
  const complete = {
    id: `${Date.now()}-${Math.random().toString(36).slice(2, 9)}`,
    timestamp: new Date().toISOString(),
    sessionId: "demo",
    cwd: process.cwd(),
    ...event
  };
  const state = await recordEvent(dataDir, complete);
  if (await isRunning()) {
    await fetch(`${endpoint}/api/events`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ ...complete, state })
    });
  }
}

if (command === "start") {
  await start();
} else if (command === "status") {
  process.stdout.write(`${JSON.stringify(await readState(dataDir), null, 2)}\n`);
} else if (command === "demo") {
  await start();
  const events = [
    { type: "edit", addedLines: 8, removedLines: 0, addedChars: 220, removedChars: 0 },
    { type: "edit", addedLines: 18, removedLines: 4, addedChars: 540, removedChars: 96 },
    { type: "verification", category: "test", success: true },
    { type: "turn-stop" }
  ];
  for (const event of events) {
    await emit(event);
    await new Promise((resolve) => setTimeout(resolve, 850));
  }
} else {
  process.stderr.write("Usage: power-mode.mjs <start|demo|status> [--open]\n");
  process.exitCode = 2;
}
