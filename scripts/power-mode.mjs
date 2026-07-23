#!/usr/bin/env node
import { spawn, spawnSync } from "node:child_process";
import { mkdir, mkdtemp, open, readFile, rm, stat, unlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
  nativeConfigFromEnvironment,
  nativeStreamEndpointFromEnvironment,
  serviceEndpointFromEnvironment
} from "../src/config.mjs";
import { powerModeDataDir } from "../src/paths.mjs";
import { bearerHeaders, ensureServiceToken } from "../src/auth.mjs";
import { isNativeOverlayCommand } from "../src/native-process.mjs";
import { isPowerModeServerCommand, pluginIdentity, serviceMatchesPlugin } from "../src/service-identity.mjs";
import { initialState, reduceState } from "../src/state.mjs";
import { powerModeStatus } from "../src/status.mjs";
import { powerModeDoctor, renderDoctorReport } from "../src/doctor.mjs";
import { purgePowerModeData, resetOverlaySettings } from "../src/maintenance.mjs";
import { readState } from "../src/storage.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const identity = await pluginIdentity(root);
const dataDir = powerModeDataDir();
const command = process.argv[2] || "start";
const endpoint = serviceEndpointFromEnvironment(process.env);
const nativeDir = path.join(dataDir, "native");
const nativeBinary = path.join(nativeDir, "codex-power-mode-overlay");
const nativePidFile = path.join(nativeDir, "overlay.pid");
const nativeConfigFile = path.join(nativeDir, "overlay-config.json");
const nativeStartLockFile = path.join(nativeDir, "overlay-start.lock");

async function authenticatedHeaders(headers = {}) {
  return bearerHeaders(await ensureServiceToken(dataDir), headers);
}

async function serviceHealth() {
  try {
    const response = await fetch(`${endpoint}/api/health`, {
      headers: await authenticatedHeaders(),
      signal: AbortSignal.timeout(250)
    });
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

let previewState = { ...initialState };

async function emitPreview(event) {
  const complete = {
    id: `${Date.now()}-${Math.random().toString(36).slice(2, 9)}`,
    timestamp: new Date().toISOString(),
    sessionId: "demo",
    preview: true,
    cwd: process.cwd(),
    ...event
  };
  previewState = reduceState(previewState, complete);
  await broadcast({ ...complete, state: previewState });
}

async function broadcast(event) {
  if (!(await isRunning())) await start();
  await fetch(`${endpoint}/api/events`, {
    method: "POST",
    headers: await authenticatedHeaders({ "content-type": "application/json" }),
    body: JSON.stringify(event)
  });
}

async function restorePreview(realState) {
  await broadcast({
    type: "connected",
    id: `${Date.now()}-preview-restore`,
    timestamp: new Date().toISOString(),
    sessionId: "demo",
    preview: true,
    state: realState
  });
}

async function playPreview(events, delayMs) {
  await start();
  const realState = await readState(dataDir);
  previewState = { ...initialState };
  try {
    for (const event of events) {
      await emitPreview(event);
      await new Promise((resolve) => setTimeout(resolve, delayMs));
    }
  } finally {
    await restorePreview(realState);
  }
}

async function playEnergyShowcase(delayMs = 1450) {
  await start();
  const realState = await readState(dataDir);
  const tierValues = [45, 170, 340, 580, 820, 960, 999];
  try {
    for (const momentum of tierValues) {
      const timestamp = new Date().toISOString();
      await broadcast({
        type: "activity-start",
        id: `${Date.now()}-tier-${momentum}`,
        timestamp,
        sessionId: "demo",
        preview: true,
        phase: "act",
        toolGroup: "change",
        state: {
          ...initialState,
          phase: "act",
          status: "working",
          momentum,
          bestMomentum: 999,
          energyUpdatedAt: timestamp,
          currentActivity: `Energy tier ${momentum}`,
          lastActivityAt: timestamp,
          sessionId: "demo"
        }
      });
      await new Promise((resolve) => setTimeout(resolve, delayMs));
    }
  } finally {
    await restorePreview(realState);
  }
}

async function playCompletionShowcase(delayMs = 2200) {
  await start();
  const realState = await readState(dataDir);
  const outcomes = [
    { completion: "verified", status: "completed", momentum: 999 },
    { completion: "unverified", status: "completed", momentum: 820 },
    { completion: "cancelled", status: "cancelled", momentum: 580 },
    { completion: "no-change", status: "completed", momentum: 340 }
  ];
  try {
    for (const outcome of outcomes) {
      const timestamp = new Date().toISOString();
      await broadcast({
        type: "turn-stop",
        id: `${Date.now()}-complete-${outcome.completion}`,
        timestamp,
        sessionId: "demo",
        preview: true,
        state: {
          ...initialState,
          phase: "complete",
          status: outcome.status,
          momentum: outcome.momentum,
          bestMomentum: 999,
          completion: outcome.completion,
          energyUpdatedAt: timestamp,
          lastActivityAt: timestamp,
          stoppedAt: timestamp,
          sessionId: "demo"
        }
      });
      await new Promise((resolve) => setTimeout(resolve, delayMs));
    }
  } finally {
    await restorePreview(realState);
  }
}

async function replay() {
  await start();
  const realState = await readState(dataDir);
  let records;
  try {
    records = (await readFile(path.join(dataDir, "events.ndjson"), "utf8"))
      .split(/\r?\n/).filter(Boolean).map((line) => JSON.parse(line));
  } catch (error) {
    if (error.code === "ENOENT") throw new Error("No recorded events yet. Run a Codex task first.");
    throw error;
  }
  try {
    for (const event of records.slice(-40)) {
      await broadcast({ ...event, sessionId: "demo", preview: true });
      await new Promise((resolve) => setTimeout(resolve, 420));
    }
  } finally {
    await restorePreview(realState);
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
    return await nativeProcessMatches(pid) ? pid : null;
  } catch {
    return null;
  }
}

async function nativeProcessMatches(pid) {
  if (!(await processIsAlive(pid))) return false;
  const processInfo = spawnSync("ps", ["-p", String(pid), "-o", "command="], { encoding: "utf8" });
  return processInfo.status === 0 && isNativeOverlayCommand(processInfo.stdout, nativeBinary);
}

async function withNativeStartLock(operation) {
  await mkdir(nativeDir, { recursive: true });
  let handle;
  for (let attempt = 0; attempt < 200; attempt += 1) {
    try {
      handle = await open(nativeStartLockFile, "wx");
      await handle.writeFile(JSON.stringify({ pid: process.pid, acquiredAt: new Date().toISOString() }));
      break;
    } catch (error) {
      if (error.code !== "EEXIST") throw error;
      try {
        const [contents, info] = await Promise.all([readFile(nativeStartLockFile, "utf8"), stat(nativeStartLockFile)]);
        let ownerPid = null;
        try {
          ownerPid = Number.parseInt(JSON.parse(contents).pid, 10);
        } catch {
          // A process can exit after creating the lock but before writing its identity.
        }
        const ownerIsAlive = Number.isInteger(ownerPid) && ownerPid > 0 && await processIsAlive(ownerPid);
        if (Date.now() - info.mtimeMs >= 10_000 && !ownerIsAlive) {
          await unlink(nativeStartLockFile);
          continue;
        }
      } catch (lockError) {
        if (lockError.code === "ENOENT") continue;
      }
      await new Promise((resolve) => setTimeout(resolve, 50));
    }
  }
  if (!handle) throw new Error("Could not acquire Power Mode native startup lock");
  try {
    return await operation();
  } finally {
    await handle.close();
    await unlink(nativeStartLockFile).catch(() => {});
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
    "-framework", "AppKit", "-framework", "Foundation", "-framework", "ApplicationServices",
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
      "-framework", "AppKit", "-framework", "Foundation", "-framework", "ApplicationServices",
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

async function nativeOverlayBuildIsCurrent() {
  const source = path.join(root, "native/macos/PowerModeOverlay.swift");
  const [sourceTime, binaryTime] = await Promise.all([
    stat(source).then((info) => info.mtimeMs),
    stat(nativeBinary).then((info) => info.mtimeMs).catch(() => 0)
  ]);
  return binaryTime >= sourceTime;
}

async function startNative() {
  await start();
  await withNativeStartLock(async () => {
    const existing = await currentNativePid();
    const streamEndpoint = nativeStreamEndpointFromEnvironment(process.env);
    const currentConfiguration = await readFile(nativeConfigFile, "utf8").then(JSON.parse).catch(() => ({}));
    const nextConfiguration = {
      ...nativeConfigFromEnvironment(process.env, currentConfiguration),
      endpoint: streamEndpoint
    };
    if (existing && JSON.stringify(currentConfiguration) === JSON.stringify(nextConfiguration) && await nativeOverlayBuildIsCurrent()) {
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
        CODEX_POWER_MODE_TOKEN: await ensureServiceToken(dataDir),
        CODEX_POWER_MODE_CONFIG_PATH: nativeConfigFile
      }
    });
    child.unref();
    await writeFile(nativePidFile, `${child.pid}\n`);
    for (let attempt = 0; attempt < 40 && !(await nativeProcessMatches(child.pid)); attempt += 1) {
      await new Promise((resolve) => setTimeout(resolve, 25));
    }
    if (!(await nativeProcessMatches(child.pid))) {
      await unlink(nativePidFile).catch(() => {});
      throw new Error("Native overlay did not become ready after launch");
    }
    process.stdout.write(`Native overlay started (PID ${child.pid})\n`);
  });
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

async function stopService() {
  const pid = await listenerPid();
  if (!pid) {
    process.stdout.write("Power Mode service is not running\n");
    return;
  }
  process.kill(pid, "SIGTERM");
  for (let attempt = 0; attempt < 40 && await processIsAlive(pid); attempt += 1) {
    await new Promise((resolve) => setTimeout(resolve, 25));
  }
  if (await processIsAlive(pid)) throw new Error(`Power Mode service (PID ${pid}) did not stop`);
  process.stdout.write(`Power Mode service stopped (PID ${pid})\n`);
}

async function stopAll() {
  await stopNative();
  await stopService();
}

function requireConfirmation(action) {
  if (process.argv.includes("--yes")) return true;
  process.stderr.write(`${action} requires explicit confirmation. Run the same command with --yes.\n`);
  process.exitCode = 2;
  return false;
}

async function resetSettings() {
  if (!requireConfirmation("Resetting display settings")) return;
  await stopNative();
  await resetOverlaySettings(dataDir);
  await startNative();
  process.stdout.write("Power Mode display settings restored to defaults; history was preserved\n");
}

async function purgeData() {
  if (!requireConfirmation("Deleting Power Mode settings, history, and local authentication")) return;
  await stopAll();
  await purgePowerModeData(dataDir);
  process.stdout.write("Power Mode local data removed; the installed plugin was not changed\n");
}

async function status() {
  const [health, nativePid, state, nativeConfiguration] = await Promise.all([
    serviceHealth(),
    currentNativePid(),
    readState(dataDir),
    readFile(nativeConfigFile, "utf8").then(JSON.parse).catch(() => null)
  ]);
  return powerModeStatus({ health, nativePid, nativeConfiguration, state, endpoint });
}

function processCounts() {
  if (process.platform === "win32") return { serverProcessCount: 1, nativeProcessCount: 0 };
  const listing = spawnSync("ps", ["-axo", "command="], { encoding: "utf8" });
  const commands = listing.status === 0 ? listing.stdout.split(/\r?\n/).filter(Boolean) : [];
  return {
    serverProcessCount: commands.filter(isPowerModeServerCommand).length,
    nativeProcessCount: commands.filter((value) => isNativeOverlayCommand(value, nativeBinary)).length
  };
}

async function doctor() {
  const snapshot = await status();
  let accessibility = null;
  if (process.platform === "darwin" && snapshot.nativeOverlay?.configuration?.typingCombo === true) {
    const diagnostic = spawnSync(nativeBinary, [], {
      encoding: "utf8",
      timeout: 3_000,
      env: {
        ...process.env,
        CODEX_POWER_MODE_ACCESSIBILITY_SELF_TEST: "1",
        CODEX_POWER_MODE_CONFIG_PATH: nativeConfigFile
      }
    });
    if (diagnostic.status === 0) {
      try { accessibility = JSON.parse(diagnostic.stdout); } catch { /* Report the permission as unavailable below. */ }
    }
  }
  const report = powerModeDoctor({
    status: snapshot,
    identity,
    expectedDataDir: dataDir,
    platform: process.platform,
    ...processCounts(),
    accessibility
  });
  process.stdout.write(process.argv.includes("--json") ? `${JSON.stringify(report, null, 2)}\n` : renderDoctorReport(report));
  if (report.overall === "fail") process.exitCode = 1;
}

if (command === "start") {
  await start();
} else if (command === "status") {
  process.stdout.write(`${JSON.stringify(await status(), null, 2)}\n`);
} else if (command === "doctor") {
  await doctor();
} else if (command === "demo") {
  const events = [
    { type: "activity-start", phase: "observe", toolGroup: "search" },
    { type: "activity-start", phase: "act", toolGroup: "change" },
    { type: "edit", addedLines: 18, removedLines: 4, addedChars: 540, removedChars: 96 },
    { type: "activity-start", phase: "verify", category: "test", toolGroup: "command" },
    { type: "verification", category: "test", success: true },
    { type: "turn-stop" }
  ];
  await playPreview(events, 850);
} else if (command === "showcase") {
  const events = [
    { type: "activity-start", phase: "observe", toolGroup: "prompt" },
    { type: "input-charge", phase: "observe", toolGroup: "prompt", inputCombo: 18 },
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
    { type: "activity-start", phase: "act", toolGroup: "change" },
    { type: "edit", addedLines: 3, removedLines: 1, addedChars: 84, removedChars: 24 },
    { type: "activity-start", phase: "act", toolGroup: "command" },
    { type: "edit", addedLines: 4, removedLines: 1, addedChars: 112, removedChars: 24 },
    { type: "activity-start", phase: "act", toolGroup: "change" },
    { type: "edit", addedLines: 2, removedLines: 1, addedChars: 64, removedChars: 20 },
    { type: "activity-start", phase: "act", toolGroup: "command" },
    { type: "edit", addedLines: 5, removedLines: 2, addedChars: 136, removedChars: 42 },
    { type: "activity-start", phase: "act", toolGroup: "change" },
    { type: "edit", addedLines: 3, removedLines: 0, addedChars: 78, removedChars: 0 },
    { type: "activity-start", phase: "act", toolGroup: "command" },
    { type: "edit", addedLines: 2, removedLines: 1, addedChars: 58, removedChars: 18 },
    { type: "activity-start", phase: "verify", category: "test", toolGroup: "command" },
    { type: "verification", category: "test", success: true },
    { type: "turn-stop" }
  ];
  await playPreview(events, 850);
} else if (command === "energy-showcase") {
  await playEnergyShowcase();
} else if (command === "completion-showcase") {
  await playCompletionShowcase();
} else if (command === "replay") {
  await replay();
} else if (command === "native") {
  await startNative();
} else if (command === "native-stop") {
  await stopNative();
} else if (command === "stop") {
  await stopAll();
} else if (command === "reset-settings") {
  await resetSettings();
} else if (command === "purge-data") {
  await purgeData();
} else {
  process.stderr.write("Usage: power-mode.mjs <start|native|native-stop|stop|reset-settings|purge-data|demo|showcase|energy-showcase|completion-showcase|replay|status|doctor> [--open|--json|--yes]\n");
  process.exitCode = 2;
}
