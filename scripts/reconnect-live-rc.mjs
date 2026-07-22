#!/usr/bin/env node
import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import { mkdir, writeFile } from "node:fs/promises";
import http from "node:http";
import path from "node:path";
import process from "node:process";

const root = path.resolve(import.meta.dirname, "..");
const sourceControl = path.join(root, "scripts", "power-mode.mjs");
const outputFlag = process.argv.indexOf("--output");
const output = path.resolve(outputFlag >= 0 && process.argv[outputFlag + 1]
  ? process.argv[outputFlag + 1]
  : ".power-mode/reconnect-live-rc.json");

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

function closeServer(server) {
  return new Promise((resolve) => server.listening ? server.close(resolve) : resolve());
}

if (process.platform !== "darwin") throw new Error("Live reconnect validation currently requires macOS");
const before = readStatus(sourceControl, root);
const servicePid = before.service?.servicePid;
const hudPid = before.nativeOverlay?.pid;
const controlRoot = before.service?.serviceRoot;
const controlScript = controlRoot ? path.join(controlRoot, "scripts", "power-mode.mjs") : sourceControl;
const endpoint = new URL(before.nativeOverlay?.configuration?.endpoint ?? "http://127.0.0.1:4737/api/stream");
const port = Number(endpoint.port || 80);
assert.ok(Number.isInteger(servicePid) && servicePid > 0);
assert.ok(Number.isInteger(hudPid) && hudPid > 0);
assert.ok(controlRoot);
assert.ok(processCommand(servicePid).includes(path.join(controlRoot, "scripts", "server.mjs")), "Refusing to stop an unrecognized service process");
const originalConfiguration = before.nativeOverlay.configuration;
const attempts = [];
let attemptsReady;
const enoughAttempts = new Promise((resolve) => { attemptsReady = resolve; });
const rejectionServer = http.createServer((request, response) => {
  if (request.url?.startsWith(endpoint.pathname)) {
    attempts.push(Date.now());
    if (attempts.length === 3) attemptsReady();
  }
  response.writeHead(503, { connection: "close", "content-type": "text/plain" });
  response.end("temporarily unavailable");
});
let restored = false;

try {
  process.kill(servicePid, "SIGTERM");
  await waitFor(() => !processIsAlive(servicePid), 3_000, "Service did not stop cleanly");
  const disconnectedAt = Date.now();
  await new Promise((resolve, reject) => rejectionServer.listen(port, "127.0.0.1", resolve).once("error", reject));
  await Promise.race([
    enoughAttempts,
    new Promise((_, reject) => setTimeout(() => reject(new Error("HUD did not perform three bounded reconnect attempts")), 10_000))
  ]);

  const delays = [
    attempts[0] - disconnectedAt,
    attempts[1] - attempts[0],
    attempts[2] - attempts[1]
  ];
  assert.ok(delays[0] >= 500 && delays[0] <= 2_500, `First retry was ${delays[0]} ms`);
  assert.ok(delays[1] >= 1_500 && delays[1] <= 3_500, `Second retry was ${delays[1]} ms`);
  assert.ok(delays[2] >= 3_000 && delays[2] <= 6_000, `Third retry was ${delays[2]} ms`);
  assert.equal(processIsAlive(hudPid), true, "HUD exited during repeated connection failures");

  await closeServer(rejectionServer);
  await run(controlScript, controlRoot, "start");
  const recovered = await waitFor(() => {
    const status = readStatus(controlScript, controlRoot);
    return status.connection?.hudConnected === true ? status : null;
  }, 12_000, "HUD did not recover after bounded reconnect failures");
  restored = true;
  const doctor = JSON.parse(await run(controlScript, controlRoot, "doctor", ["--json"]));
  const checks = Object.fromEntries(doctor.checks.map((check) => [check.id, check.level]));
  assert.equal(recovered.nativeOverlay?.pid, hudPid);
  assert.deepEqual(recovered.nativeOverlay?.configuration, originalConfiguration);
  assert.equal(checks["service-instance"], "ok");
  assert.equal(checks["native-instance"], "ok");
  assert.equal(checks["hud-connection"], "ok");

  const report = {
    schemaVersion: 1,
    generatedAt: new Date().toISOString(),
    pluginVersion: recovered.service?.serviceVersion ?? null,
    rejectedAttempts: attempts.length,
    observedDelayMilliseconds: delays,
    expectedDelaySeconds: [1, 2, 4],
    recoveredAfterRepeatedFailures: true,
    hudProcessPreserved: true,
    oneService: true,
    oneHud: true,
    settingsPreserved: true,
    realLifecycleEventsInjected: 0,
    privacy: "No task identifiers, prompts, code, commands, key values, cursor coordinates, tokens, or local paths are written to this report"
  };
  await mkdir(path.dirname(output), { recursive: true });
  await writeFile(output, `${JSON.stringify(report, null, 2)}\n`, { mode: 0o600 });
  process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
} finally {
  await closeServer(rejectionServer).catch(() => {});
  if (!restored) await run(controlScript, controlRoot, "start").catch(() => {});
}
