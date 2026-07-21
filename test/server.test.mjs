import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import http from "node:http";
import net from "node:net";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

async function freePort() {
  const probe = net.createServer();
  await new Promise((resolve, reject) => probe.listen(0, "127.0.0.1", resolve).once("error", reject));
  const { port } = probe.address();
  await new Promise((resolve) => probe.close(resolve));
  return port;
}

function waitForOutput(stream, pattern, timeoutMs = 2_000) {
  return new Promise((resolve, reject) => {
    let output = "";
    const timeout = setTimeout(() => reject(new Error(`Timed out waiting for ${pattern}`)), timeoutMs);
    stream.on("data", (chunk) => {
      output += chunk;
      if (!pattern.test(output)) return;
      clearTimeout(timeout);
      resolve(output);
    });
  });
}

function waitForExit(child, timeoutMs = 2_000) {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error("Server did not exit after SIGTERM")), timeoutMs);
    child.once("exit", (code, signal) => {
      clearTimeout(timeout);
      resolve({ code, signal });
    });
  });
}

test("event service exits cleanly while an SSE overlay is connected", async () => {
  const dataDir = await mkdtemp(path.join(os.tmpdir(), "codex-power-mode-server-"));
  const port = await freePort();
  const child = spawn(process.execPath, [path.join(root, "scripts/server.mjs"), "--port", String(port), "--data-dir", dataDir], {
    cwd: root,
    stdio: ["ignore", "pipe", "pipe"]
  });
  let request;

  try {
    await waitForOutput(child.stdout, /Codex Power Mode HUD/);
    const connected = new Promise((resolve, reject) => {
      request = http.get(`http://127.0.0.1:${port}/api/stream`, (response) => {
        assert.equal(response.statusCode, 200);
        response.once("data", resolve);
      });
      request.once("error", reject);
    });
    await connected;

    child.kill("SIGTERM");
    const result = await waitForExit(child);
    assert.equal(result.code, 0);
  } finally {
    request?.destroy();
    if (child.exitCode === null && child.signalCode === null) child.kill("SIGKILL");
    await rm(dataDir, { recursive: true, force: true });
  }
});

test("event service health identifies the running plugin build", async () => {
  const dataDir = await mkdtemp(path.join(os.tmpdir(), "codex-power-mode-health-"));
  const port = await freePort();
  const child = spawn(process.execPath, [path.join(root, "scripts/server.mjs"), "--port", String(port), "--data-dir", dataDir], {
    cwd: root,
    stdio: ["ignore", "pipe", "pipe"]
  });

  try {
    await waitForOutput(child.stdout, /Codex Power Mode HUD/);
    const response = await fetch(`http://127.0.0.1:${port}/api/health`);
    const health = await response.json();
    const manifest = JSON.parse(await readFile(path.join(root, ".codex-plugin/plugin.json"), "utf8"));

    assert.equal(health.ok, true);
    assert.equal(health.serviceVersion, manifest.version);
    assert.equal(health.serviceRoot, root);
    assert.equal(health.servicePid, child.pid);
  } finally {
    child.kill("SIGTERM");
    await waitForExit(child).catch(() => child.kill("SIGKILL"));
    await rm(dataDir, { recursive: true, force: true });
  }
});

test("event service records concurrent activity without replacing the active HUD session", async () => {
  const dataDir = await mkdtemp(path.join(os.tmpdir(), "codex-power-mode-arbitration-"));
  const port = await freePort();
  const child = spawn(process.execPath, [path.join(root, "scripts/server.mjs"), "--port", String(port), "--data-dir", dataDir], {
    cwd: root,
    stdio: ["ignore", "pipe", "pipe"]
  });
  const post = (body) => fetch(`http://127.0.0.1:${port}/api/events`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body)
  });

  try {
    await waitForOutput(child.stdout, /Codex Power Mode HUD/);
    const first = await post({
      type: "activity-start",
      sessionId: "desktop",
      timestamp: new Date(1_000).toISOString(),
      state: { sessionId: "desktop", phase: "act", status: "working", momentum: 2 }
    });
    const second = await post({
      type: "activity-start",
      sessionId: "cli",
      timestamp: new Date(2_000).toISOString(),
      state: { sessionId: "cli", phase: "act", status: "working", momentum: 99 }
    });

    assert.equal((await first.json()).displayed, true);
    assert.equal((await second.json()).displayed, false);

    const state = await (await fetch(`http://127.0.0.1:${port}/api/state`)).json();
    const health = await (await fetch(`http://127.0.0.1:${port}/api/health`)).json();
    assert.equal(state.sessionId, "desktop");
    assert.equal(state.momentum, 2);
    assert.equal(health.activity.realEventsReceived, 2);
    assert.equal(health.session.activeSessionId, "desktop");
    assert.equal(health.session.suppressedEvents, 1);

    await mkdir(path.join(dataDir, "native"), { recursive: true });
    await writeFile(path.join(dataDir, "native", "overlay-config.json"), JSON.stringify({ activitySource: "global" }));
    const global = await post({
      type: "activity-start",
      sessionId: "cli",
      timestamp: new Date(3_000).toISOString(),
      state: { sessionId: "cli", phase: "act", status: "working", momentum: 4 }
    });
    assert.equal((await global.json()).displayed, true);

    const globalState = await (await fetch(`http://127.0.0.1:${port}/api/state`)).json();
    const globalHealth = await (await fetch(`http://127.0.0.1:${port}/api/health`)).json();
    assert.equal(globalState.sessionId, "cli");
    assert.equal(globalState.momentum, 4);
    assert.equal(globalHealth.activity.realEventsReceived, 3);
    assert.equal(globalHealth.session.activitySource, "global");
  } finally {
    child.kill("SIGTERM");
    await waitForExit(child).catch(() => child.kill("SIGKILL"));
    await rm(dataDir, { recursive: true, force: true });
  }
});
