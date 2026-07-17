#!/usr/bin/env node
import { spawn, spawnSync } from "node:child_process";
import { mkdir, readFile, stat, unlink, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { recordEvent, readState } from "../src/storage.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const dataDir = path.resolve(process.env.CODEX_POWER_MODE_DATA || path.join(root, ".power-mode"));
const command = process.argv[2] || "start";
const endpoint = "http://127.0.0.1:4737";
const nativeDir = path.join(dataDir, "native");
const nativeBinary = path.join(nativeDir, "codex-power-mode-overlay");
const nativePidFile = path.join(nativeDir, "overlay.pid");

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

async function broadcast(event) {
  if (!(await isRunning())) await start();
  await fetch(`${endpoint}/api/events`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(event)
  });
}

async function replay() {
  await start();
  let records;
  try {
    records = (await readFile(path.join(dataDir, "events.ndjson"), "utf8"))
      .split(/\r?\n/).filter(Boolean).map((line) => JSON.parse(line));
  } catch (error) {
    if (error.code === "ENOENT") throw new Error("No recorded events yet. Run Codex or `npm run demo` first.");
    throw error;
  }
  for (const event of records.slice(-40)) {
    await broadcast(event);
    await new Promise((resolve) => setTimeout(resolve, 420));
  }
}

async function processIsAlive(pid) {
  if (!Number.isInteger(pid) || pid <= 0) return false;
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

async function currentNativePid() {
  try {
    const pid = Number((await readFile(nativePidFile, "utf8")).trim());
    return await processIsAlive(pid) ? pid : null;
  } catch {
    return null;
  }
}

async function buildNativeOverlay() {
  if (process.platform !== "darwin") throw new Error("The native overlay currently supports macOS only. Use `npm start` for the browser HUD.");
  await mkdir(nativeDir, { recursive: true });
  const source = path.join(root, "native/macos/PowerModeOverlay.swift");
  const sourceTime = (await stat(source)).mtimeMs;
  const binaryTime = await stat(nativeBinary).then((info) => info.mtimeMs).catch(() => 0);
  if (binaryTime >= sourceTime) return;
  const result = spawnSync("xcrun", [
    "swiftc", "-swift-version", "5", "-parse-as-library", "-O", source,
    "-framework", "AppKit", "-framework", "Foundation",
    "-o", nativeBinary
  ], { cwd: root, encoding: "utf8" });
  if (result.status !== 0) throw new Error(`Native overlay build failed:\n${result.stderr || result.stdout}`);
}

async function startNative() {
  await start();
  const existing = await currentNativePid();
  if (existing) {
    process.stdout.write(`Native overlay already running (PID ${existing})\n`);
    return;
  }
  await buildNativeOverlay();
  const child = spawn(nativeBinary, [], {
    detached: true,
    stdio: "ignore",
    env: {
      ...process.env,
      CODEX_POWER_MODE_URL: `${endpoint}/api/stream`
    }
  });
  child.unref();
  await writeFile(nativePidFile, `${child.pid}\n`);
  process.stdout.write(`Native overlay started (PID ${child.pid})\n`);
}

async function stopNative() {
  const pid = await currentNativePid();
  if (!pid) {
    await unlink(nativePidFile).catch(() => {});
    process.stdout.write("Native overlay is not running\n");
    return;
  }
  process.kill(pid, "SIGTERM");
  await unlink(nativePidFile).catch(() => {});
  process.stdout.write(`Native overlay stopped (PID ${pid})\n`);
}

if (command === "start") {
  await start();
} else if (command === "status") {
  process.stdout.write(`${JSON.stringify(await readState(dataDir), null, 2)}\n`);
} else if (command === "demo") {
  await start();
  const events = [
    { type: "activity-start", phase: "observe", toolGroup: "search" },
    { type: "activity-start", phase: "act", toolGroup: "change" },
    { type: "edit", addedLines: 18, removedLines: 4, addedChars: 540, removedChars: 96 },
    { type: "activity-start", phase: "verify", category: "test", toolGroup: "command" },
    { type: "verification", category: "test", success: true },
    { type: "turn-stop" }
  ];
  for (const event of events) {
    await emit(event);
    await new Promise((resolve) => setTimeout(resolve, 850));
  }
} else if (command === "replay") {
  await replay();
} else if (command === "native") {
  await startNative();
} else if (command === "native-stop") {
  await stopNative();
} else {
  process.stderr.write("Usage: power-mode.mjs <start|native|native-stop|demo|replay|status> [--open]\n");
  process.exitCode = 2;
}
