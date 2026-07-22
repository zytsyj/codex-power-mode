#!/usr/bin/env node
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdtemp, readFile, rm, stat, writeFile, mkdir } from "node:fs/promises";
import net from "node:net";
import os from "node:os";
import path from "node:path";
import process from "node:process";
import { bearerHeaders, ensureServiceToken, serviceTokenPath } from "../src/auth.mjs";
import { powerModeDoctor } from "../src/doctor.mjs";

const root = path.resolve(import.meta.dirname, "..");
const outputFlag = process.argv.indexOf("--output");
const output = path.resolve(outputFlag >= 0 && process.argv[outputFlag + 1]
  ? process.argv[outputFlag + 1]
  : ".power-mode/security-rc.json");

async function freePort() {
  const probe = net.createServer();
  await new Promise((resolve, reject) => probe.listen(0, "127.0.0.1", resolve).once("error", reject));
  const { port } = probe.address();
  await new Promise((resolve) => probe.close(resolve));
  return port;
}

function waitForOutput(stream, pattern, timeoutMs = 3_000) {
  return new Promise((resolve, reject) => {
    let outputText = "";
    const timeout = setTimeout(() => reject(new Error("Timed out starting isolated security service")), timeoutMs);
    stream.on("data", (chunk) => {
      outputText += chunk;
      if (!pattern.test(outputText)) return;
      clearTimeout(timeout);
      resolve();
    });
  });
}

function waitForExit(child, timeoutMs = 2_000) {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error("Isolated security service did not stop")), timeoutMs);
    child.once("exit", () => {
      clearTimeout(timeout);
      resolve();
    });
  });
}

const checks = [];
function passed(id, evidence) {
  checks.push({ id, pass: true, evidence });
}

const dataDir = await mkdtemp(path.join(os.tmpdir(), "codex-power-mode-security-rc-"));
const port = await freePort();
const endpoint = `http://127.0.0.1:${port}`;
const serverSource = await readFile(path.join(root, "scripts", "server.mjs"), "utf8");
assert.match(serverSource, /server\.listen\(port, "127\.0\.0\.1"/);
passed("loopback-binding", "Server source fixes the listener host to IPv4 loopback");

const child = spawn(process.execPath, [path.join(root, "scripts", "server.mjs"), "--port", String(port), "--data-dir", dataDir], {
  cwd: root,
  stdio: ["ignore", "pipe", "pipe"]
});

try {
  await waitForOutput(child.stdout, /Codex Power Mode HUD/);
  const token = await ensureServiceToken(dataDir);
  assert.equal((await stat(serviceTokenPath(dataDir))).mode & 0o777, 0o600);
  passed("installation-token", "One 256-bit token is stored with owner-only permissions");

  assert.equal((await fetch(`${endpoint}/api/health`)).status, 401);
  assert.equal((await fetch(`${endpoint}/api/browser-token`)).status, 403);
  passed("service-authentication", "Unauthenticated API and browser-token requests are rejected");

  const browserTokenResponse = await fetch(`${endpoint}/api/browser-token`, {
    headers: { "sec-fetch-site": "same-origin", origin: endpoint }
  });
  assert.equal(browserTokenResponse.status, 200);
  const browserToken = (await browserTokenResponse.json()).token;
  assert.notEqual(browserToken, token);
  const streamAbort = new AbortController();
  const stream = await fetch(`${endpoint}/api/stream?token=${browserToken}`, { signal: streamAbort.signal });
  assert.equal(stream.status, 200);
  streamAbort.abort();
  assert.equal((await fetch(`${endpoint}/api/health?token=${browserToken}`)).status, 401);
  passed("browser-token-scope", "Same-origin browser token is process-scoped and stream-only");

  const crossOrigin = await fetch(`${endpoint}/api/health`, {
    headers: bearerHeaders(token, { origin: "https://example.invalid" })
  });
  assert.equal(crossOrigin.status, 403);
  passed("origin-validation", "Authenticated cross-origin API requests are rejected");

  const wrongMediaType = await fetch(`${endpoint}/api/events`, {
    method: "POST",
    headers: bearerHeaders(token, { "content-type": "text/plain" }),
    body: "{}"
  });
  assert.equal(wrongMediaType.status, 415);
  const malformed = await fetch(`${endpoint}/api/events`, {
    method: "POST",
    headers: bearerHeaders(token, { "content-type": "application/json" }),
    body: "{"
  });
  assert.equal(malformed.status, 400);
  const oversized = await fetch(`${endpoint}/api/events`, {
    method: "POST",
    headers: bearerHeaders(token, { "content-type": "application/json" }),
    body: JSON.stringify({ payload: "x".repeat(1_000_001) })
  });
  assert.equal(oversized.status, 413);
  passed("payload-boundaries", "Non-JSON, malformed JSON, and bodies above 1 MB are rejected");

  const nestedSensitive = await fetch(`${endpoint}/api/events`, {
    method: "POST",
    headers: bearerHeaders(token, { "content-type": "application/json; charset=utf-8" }),
    body: JSON.stringify({
      type: "activity-start",
      timestamp: new Date().toISOString(),
      sessionId: "security-rc",
      metadata: { nested: [{ authorization: "must-not-enter-service" }] }
    })
  });
  assert.equal(nestedSensitive.status, 400);
  passed("sensitive-field-rejection", "Sensitive keys are rejected recursively before event processing");

  const privateMarker = "/private/example/user/path";
  const secretMarker = "0123456789abcdef".repeat(4);
  const diagnostic = powerModeDoctor({
    status: {
      service: { running: true, ok: true, serviceVersion: "rc", dataDir: privateMarker, token: secretMarker },
      nativeOverlay: { running: true, configuration: { typingCombo: false } },
      connection: { hudConnected: true, hookActivity: "waiting-for-task", currentSessionId: "private-session" }
    },
    identity: { version: "rc" },
    expectedDataDir: privateMarker,
    platform: "darwin",
    serverProcessCount: 1,
    nativeProcessCount: 1
  });
  const diagnosticText = JSON.stringify(diagnostic);
  assert.equal(diagnosticText.includes(privateMarker), false);
  assert.equal(diagnosticText.includes(secretMarker), false);
  assert.equal(diagnosticText.includes("private-session"), false);
  passed("diagnostic-redaction", "Doctor output omits paths, tokens, and session identifiers");

  const health = await fetch(`${endpoint}/api/health`, { headers: bearerHeaders(token) });
  assert.equal(health.status, 200);
  passed("failure-isolation", "Service remains healthy after every rejected request");

  const manifest = JSON.parse(await readFile(path.join(root, ".codex-plugin", "plugin.json"), "utf8"));
  const report = {
    schemaVersion: 1,
    generatedAt: new Date().toISOString(),
    environment: { platform: `${os.platform()} ${os.release()}`, architecture: os.arch(), node: process.version },
    pluginVersion: manifest.version,
    isolatedService: true,
    realLifecycleEventsInjected: 0,
    checks,
    passed: checks.every((check) => check.pass),
    privacy: "The report contains no prompts, code, commands, key values, cursor coordinates, tokens, task identifiers, local paths, ports, or process identifiers"
  };
  await mkdir(path.dirname(output), { recursive: true });
  await writeFile(output, `${JSON.stringify(report, null, 2)}\n`, { mode: 0o600 });
  process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
} finally {
  child.kill("SIGTERM");
  await waitForExit(child).catch(() => child.kill("SIGKILL"));
  await rm(dataDir, { recursive: true, force: true });
}
