#!/usr/bin/env node
import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import process from "node:process";

const root = path.resolve(import.meta.dirname, "..");
const sourceControl = path.join(root, "scripts", "power-mode.mjs");
const outputFlag = process.argv.indexOf("--output");
const output = path.resolve(outputFlag >= 0 && process.argv[outputFlag + 1]
  ? process.argv[outputFlag + 1]
  : ".power-mode/stability-rc.json");

function run(script, cwd, command, args = []) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [script, command, ...args], { cwd, stdio: ["ignore", "pipe", "pipe"] });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (chunk) => { stdout += chunk; });
    child.stderr.on("data", (chunk) => { stderr += chunk; });
    child.once("error", reject);
    child.once("exit", (code) => code === 0 ? resolve(stdout) : reject(new Error(stderr || `${command} exited with status ${code}`)));
  });
}

function readStatus(script, cwd) {
  const result = spawnSync(process.execPath, [script, "status"], { cwd, encoding: "utf8" });
  if (result.status !== 0) throw new Error(result.stderr || "status failed");
  return JSON.parse(result.stdout);
}

function processCommand(pid) {
  const result = spawnSync("ps", ["-p", String(pid), "-o", "command="], { encoding: "utf8" });
  return result.status === 0 ? result.stdout.trim() : "";
}

function processIsAlive(pid) {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

async function waitFor(check, timeoutMs, message) {
  const deadline = Date.now() + timeoutMs;
  let lastError;
  while (Date.now() < deadline) {
    try {
      const value = await check();
      if (value) return value;
    } catch (error) {
      lastError = error;
    }
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error(lastError ? `${message}: ${lastError.message}` : message);
}

if (process.platform !== "darwin") throw new Error("RC stability sampling currently requires macOS");
const before = readStatus(sourceControl, root);
const servicePid = before.service?.servicePid;
const hudPid = before.nativeOverlay?.pid;
const controlRoot = before.service?.serviceRoot;
const controlScript = controlRoot ? path.join(controlRoot, "scripts", "power-mode.mjs") : sourceControl;
assert.ok(Number.isInteger(servicePid) && servicePid > 0, "Start the Power Mode service before running stability:rc");
assert.ok(Number.isInteger(hudPid) && hudPid > 0, "Start the native HUD before running stability:rc");
assert.ok(controlRoot, "The running service must report its plugin root");
assert.ok(processCommand(servicePid).includes(path.join(controlRoot, "scripts", "server.mjs")), "Refusing to stop an unrecognized service process");
const originalConfiguration = before.nativeOverlay.configuration;
const startedAt = Date.now();
let restored = false;

try {
  process.kill(servicePid, "SIGTERM");
  await waitFor(() => !processIsAlive(servicePid), 3_000, "Service did not stop cleanly");
  await new Promise((resolve) => setTimeout(resolve, 1_250));
  assert.equal(processIsAlive(hudPid), true, "HUD exited while its service was unavailable");

  await run(controlScript, controlRoot, "start");
  const recovered = await waitFor(() => {
    const status = readStatus(controlScript, controlRoot);
    return status.service?.servicePid !== servicePid && status.connection?.hudConnected === true ? status : null;
  }, 12_000, "HUD did not reconnect to the restarted service");
  const recoveredAt = Date.now();
  restored = true;

  const concurrentStarts = await Promise.all(Array.from({ length: 8 }, () => run(controlScript, controlRoot, "native")));
  assert.equal(concurrentStarts.length, 8);
  const finalStatus = readStatus(controlScript, controlRoot);
  const doctor = JSON.parse(await run(controlScript, controlRoot, "doctor", ["--json"]));
  const checks = Object.fromEntries(doctor.checks.map((check) => [check.id, check.level]));

  assert.equal(finalStatus.nativeOverlay?.pid, hudPid, "Concurrent starts replaced the existing HUD");
  assert.deepEqual(finalStatus.nativeOverlay?.configuration, originalConfiguration, "Restart changed the user's HUD settings");
  assert.equal(checks["service-instance"], "ok");
  assert.equal(checks["native-instance"], "ok");
  assert.equal(checks["hud-connection"], "ok");
  assert.equal(checks["data-directory"], "ok");

  const report = {
    schemaVersion: 1,
    generatedAt: new Date().toISOString(),
    pluginVersion: recovered.service?.serviceVersion ?? null,
    serviceRestarted: true,
    hudSurvivedRestart: true,
    hudReconnected: true,
    reconnectMilliseconds: recoveredAt - startedAt,
    concurrentNativeStarts: concurrentStarts.length,
    oneService: checks["service-instance"] === "ok",
    oneHud: checks["native-instance"] === "ok",
    settingsPreserved: true,
    dataDirectoryConsistent: true,
    privacy: "No task identifiers, prompts, code, commands, key values, cursor coordinates, tokens, or local paths are written to this report"
  };
  await mkdir(path.dirname(output), { recursive: true });
  await writeFile(output, `${JSON.stringify(report, null, 2)}\n`, { mode: 0o600 });
  process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
} finally {
  if (!restored) await run(controlScript, controlRoot, "start").catch(() => {});
}
