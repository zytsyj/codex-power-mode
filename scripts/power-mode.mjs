#!/usr/bin/env node
import { spawn, spawnSync } from "node:child_process";
import { mkdir, mkdtemp, readFile, rm, stat, unlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
  nativeConfigFromEnvironment,
  nativeStreamEndpointFromEnvironment,
  serviceEndpointFromEnvironment
} from "../src/config.mjs";
import { powerModeDataDir } from "../src/paths.mjs";
import { isPowerModeServerCommand, pluginIdentity, serviceMatchesPlugin } from "../src/service-identity.mjs";
import { connectionDiagnostics } from "../src/diagnostics.mjs";
import { presentationSnapshot } from "../src/state.mjs";
import { recordEvent, readState } from "../src/storage.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const identity = await pluginIdentity(root);
const dataDir = powerModeDataDir();
const command = process.argv[2] || "start";
const endpoint = serviceEndpointFromEnvironment(process.env);
const nativeDir = path.join(dataDir, "native");
const nativeBinary = path.join(nativeDir, "codex-power-mode-overlay");
const nativePidFile = path.join(nativeDir, "overlay.pid");
const nativeConfigFile = path.join(nativeDir, "overlay-config.json");

async function serviceHealth() {
  try {
    const response = await fetch(`${endpoint}/api/health`, { signal: AbortSignal.timeout(250) });
    return response.ok ? await response.json() : null;
  } catch {
    return null;
  }
}

async function isRunning() {
  return Boolean(await serviceHealth());
}

async function listenerPid() {
  const health = await serviceHealth();
  if (Number.isInteger(health?.servicePid) && health.servicePid > 0 && await processIsAlive(health.servicePid)) {
    return health.servicePid;
  }
  if (process.platform === "win32") return null;

  const port = new URL(endpoint).port;
  const listeners = spawnSync("lsof", ["-nP", `-iTCP:${port}`, "-sTCP:LISTEN", "-t"], { encoding: "utf8" });
  if (listeners.status !== 0) return null;
  for (const value of listeners.stdout.split(/\s+/).filter(Boolean)) {
    const pid = Number.parseInt(value, 10);
    if (!Number.isInteger(pid) || pid <= 0 || !(await processIsAlive(pid))) continue;
    const processInfo = spawnSync("ps", ["-p", String(pid), "-o", "command="], { encoding: "utf8" });
    if (processInfo.status === 0 && isPowerModeServerCommand(processInfo.stdout)) return pid;
  }
  return null;
}

async function replaceStaleService(health) {
  if (!health || serviceMatchesPlugin(health, identity)) return;
  const pid = await listenerPid();
  if (!pid) {
    throw new Error(`Port ${new URL(endpoint).port} is occupied by an unrecognized service`);
  }
  process.kill(pid, "SIGTERM");
  for (let attempt = 0; attempt < 40 && await isRunning(); attempt += 1) {
    await new Promise((resolve) => setTimeout(resolve, 25));
  }
  if (await isRunning()) throw new Error(`Stale Power Mode service (PID ${pid}) did not stop`);
}

async function start() {
  await replaceStaleService(await serviceHealth());
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
  if (result.status === 0) return;

  const firstError = result.stderr || result.stdout || "Unknown Swift compiler failure";
  if (!/llbuild|code object is not signed|mapped file has no Team ID/i.test(firstError)) {
    throw new Error(`Native overlay build failed:\n${firstError}`);
  }

  const compilerResult = spawnSync("xcrun", ["--find", "swiftc"], { encoding: "utf8" });
  const sdkResult = spawnSync("xcrun", ["--show-sdk-path"], { encoding: "utf8" });
  const compiler = compilerResult.stdout?.trim();
  const sdk = sdkResult.stdout?.trim();
  if (compilerResult.status !== 0 || sdkResult.status !== 0 || !compiler || !sdk) {
    throw new Error(`Native overlay build failed:\n${firstError}`);
  }

  const swiftRoot = path.resolve(path.dirname(compiler), "..");
  const llbuildSource = path.join(swiftRoot, "lib/swift/pm/llbuild/llbuild.framework");
  const repairDir = await mkdtemp(path.join(tmpdir(), "codex-power-mode-swift-"));
  const llbuildRepair = path.join(repairDir, "llbuild.framework");
  try {
    const copyResult = spawnSync("cp", ["-R", llbuildSource, llbuildRepair], { encoding: "utf8" });
    if (copyResult.status !== 0) throw new Error(copyResult.stderr || copyResult.stdout);
    const signResult = spawnSync("codesign", ["--force", "--deep", "--sign", "-", llbuildRepair], { encoding: "utf8" });
    if (signResult.status !== 0) throw new Error(signResult.stderr || signResult.stdout);
    const architecture = process.arch === "x64" ? "x86_64" : process.arch;
    const repairedResult = spawnSync(compiler, [
      "-sdk", sdk,
      "-target", `${architecture}-apple-macosx13.0`,
      "-swift-version", "5", "-parse-as-library", "-O", source,
      "-framework", "AppKit", "-framework", "Foundation",
      "-o", nativeBinary
    ], {
      cwd: root,
      encoding: "utf8",
      env: { ...process.env, DYLD_FRAMEWORK_PATH: repairDir, DYLD_FALLBACK_FRAMEWORK_PATH: repairDir }
    });
    if (repairedResult.status !== 0) throw new Error(repairedResult.stderr || repairedResult.stdout);
  } catch (error) {
    throw new Error(`Native overlay build failed:\n${firstError}\nAutomatic llbuild repair also failed:\n${error.message}`);
  } finally {
    await rm(repairDir, { recursive: true, force: true });
  }
}

async function startNative() {
  await start();
  const existing = await currentNativePid();
  const streamEndpoint = nativeStreamEndpointFromEnvironment(process.env);
  const currentConfiguration = await readFile(nativeConfigFile, "utf8").then(JSON.parse).catch(() => ({}));
  const nextConfiguration = {
    ...nativeConfigFromEnvironment(process.env, currentConfiguration),
    endpoint: streamEndpoint
  };
  if (existing && JSON.stringify(currentConfiguration) === JSON.stringify(nextConfiguration)) {
    process.stdout.write(`Native overlay already running (PID ${existing})\n`);
    return;
  }
  if (existing) {
    process.kill(existing, "SIGTERM");
    for (let attempt = 0; attempt < 20 && await processIsAlive(existing); attempt += 1) {
      await new Promise((resolve) => setTimeout(resolve, 25));
    }
  }
  await buildNativeOverlay();
  await writeFile(nativeConfigFile, `${JSON.stringify(nextConfiguration, null, 2)}\n`);
  const child = spawn(nativeBinary, [], {
    detached: true,
    stdio: "ignore",
    env: {
      ...process.env,
      CODEX_POWER_MODE_URL: streamEndpoint,
      CODEX_POWER_MODE_CONFIG_PATH: nativeConfigFile
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

async function status() {
  const [health, nativePid, state, nativeConfiguration] = await Promise.all([
    serviceHealth(),
    currentNativePid(),
    readState(dataDir),
    readFile(nativeConfigFile, "utf8").then(JSON.parse).catch(() => null)
  ]);
  return {
    service: { running: Boolean(health), url: endpoint, ...(health ?? {}) },
    nativeOverlay: { running: Boolean(nativePid), pid: nativePid, configuration: nativeConfiguration },
    connection: connectionDiagnostics({ health, nativePid, state }),
    presentation: presentationSnapshot(state),
    state
  };
}

if (command === "start") {
  await start();
} else if (command === "status") {
  process.stdout.write(`${JSON.stringify(await status(), null, 2)}\n`);
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
} else if (command === "showcase") {
  await start();
  const events = [
    { type: "activity-start", phase: "observe", toolGroup: "search" },
    { type: "activity-start", phase: "act", toolGroup: "change" },
    { type: "edit", addedLines: 14, removedLines: 3, addedChars: 420, removedChars: 72 },
    { type: "activity-start", phase: "verify", category: "test", toolGroup: "command" },
    { type: "verification", category: "test", success: true },
    { type: "permission-request", toolGroup: "command" },
    { type: "verification", category: "build", success: false },
    { type: "activity-start", phase: "act", toolGroup: "change" },
    { type: "edit", addedLines: 5, removedLines: 2, addedChars: 136, removedChars: 48 },
    { type: "activity-start", phase: "verify", category: "build", toolGroup: "command" },
    { type: "verification", category: "build", success: true },
    { type: "turn-stop" }
  ];
  for (const event of events) {
    await emit(event);
    await new Promise((resolve) => setTimeout(resolve, 1_900));
  }
} else if (command === "replay") {
  await replay();
} else if (command === "native") {
  await startNative();
} else if (command === "native-stop") {
  await stopNative();
} else {
  process.stderr.write("Usage: power-mode.mjs <start|native|native-stop|demo|showcase|replay|status> [--open]\n");
  process.exitCode = 2;
}
