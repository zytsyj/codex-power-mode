import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import http from "node:http";
import net from "node:net";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { bearerHeaders, ensureServiceToken } from "../src/auth.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

async function authorizedFetch(dataDir, url, options = {}) {
  return fetch(url, {
    ...options,
    headers: bearerHeaders(await ensureServiceToken(dataDir), options.headers)
  });
}

async function postEvent(dataDir, port, body) {
  if (body.state && body.preview !== true) {
    const sessionsDir = path.join(dataDir, "sessions");
    await mkdir(sessionsDir, { recursive: true });
    await writeFile(path.join(sessionsDir, `${body.sessionId}.json`), JSON.stringify(body.state));
  }
  return authorizedFetch(dataDir, `http://127.0.0.1:${port}/api/events`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body)
  });
}

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
    const token = await ensureServiceToken(dataDir);
    const connected = new Promise((resolve, reject) => {
      request = http.get(`http://127.0.0.1:${port}/api/stream`, {
        headers: bearerHeaders(token)
      }, (response) => {
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
    const response = await authorizedFetch(dataDir, `http://127.0.0.1:${port}/api/health`);
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

test("event service does not cache HUD assets during plugin updates", async () => {
  const dataDir = await mkdtemp(path.join(os.tmpdir(), "codex-power-mode-assets-"));
  const port = await freePort();
  const child = spawn(process.execPath, [path.join(root, "scripts/server.mjs"), "--port", String(port), "--data-dir", dataDir], {
    cwd: root,
    stdio: ["ignore", "pipe", "pipe"]
  });
  try {
    await waitForOutput(child.stdout, /Codex Power Mode HUD/);
    const [page, script, module] = await Promise.all([
      fetch(`http://127.0.0.1:${port}/`),
      fetch(`http://127.0.0.1:${port}/app.js`),
      fetch(`http://127.0.0.1:${port}/refresh-cadence.mjs`)
    ]);
    assert.equal(page.status, 200);
    assert.equal(script.status, 200);
    assert.equal(module.status, 200);
    assert.equal(page.headers.get("cache-control"), "no-store");
    assert.equal(script.headers.get("cache-control"), "no-store");
    assert.equal(module.headers.get("cache-control"), "no-store");
    assert.equal(module.headers.get("content-type"), "text/javascript; charset=utf-8");
  } finally {
    child.kill("SIGTERM");
    await waitForExit(child).catch(() => child.kill("SIGKILL"));
    await rm(dataDir, { recursive: true, force: true });
  }
});

test("event service rejects unauthorized, cross-origin, and malformed API requests without exiting", async () => {
  const dataDir = await mkdtemp(path.join(os.tmpdir(), "codex-power-mode-security-"));
  const port = await freePort();
  const endpoint = `http://127.0.0.1:${port}`;
  const child = spawn(process.execPath, [path.join(root, "scripts/server.mjs"), "--port", String(port), "--data-dir", dataDir], {
    cwd: root,
    stdio: ["ignore", "pipe", "pipe"]
  });
  try {
    await waitForOutput(child.stdout, /Codex Power Mode HUD/);
    const token = await ensureServiceToken(dataDir);
    assert.equal((await fetch(`${endpoint}/api/health`)).status, 401);
    assert.equal((await fetch(`${endpoint}/api/browser-token`)).status, 403);

    const browserToken = await fetch(`${endpoint}/api/browser-token`, {
      headers: { "sec-fetch-site": "same-origin", origin: endpoint }
    });
    assert.equal(browserToken.status, 200);
    const browserStreamToken = (await browserToken.json()).token;
    assert.match(browserStreamToken, /^[a-f0-9]{64}$/);
    assert.notEqual(browserStreamToken, token);
    assert.equal((await fetch(`${endpoint}/api/stream?token=${browserStreamToken}`)).status, 200);
    assert.equal((await fetch(`${endpoint}/api/health?token=${browserStreamToken}`)).status, 401);

    const crossOrigin = await fetch(`${endpoint}/api/health`, {
      headers: bearerHeaders(token, { origin: "https://example.com" })
    });
    assert.equal(crossOrigin.status, 403);

    const malformed = await fetch(`${endpoint}/api/events`, {
      method: "POST",
      headers: bearerHeaders(token, { "content-type": "application/json" }),
      body: "{"
    });
    assert.equal(malformed.status, 400);

    const wrongMediaType = await fetch(`${endpoint}/api/events`, {
      method: "POST",
      headers: bearerHeaders(token, { "content-type": "text/plain" }),
      body: JSON.stringify({ type: "activity-start" })
    });
    assert.equal(wrongMediaType.status, 415);

    const oversized = await fetch(`${endpoint}/api/events`, {
      method: "POST",
      headers: bearerHeaders(token, { "content-type": "application/json" }),
      body: JSON.stringify({ payload: "x".repeat(1_000_001) })
    });
    assert.equal(oversized.status, 413);

    const sensitive = await authorizedFetch(dataDir, `${endpoint}/api/events`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        type: "activity-start",
        timestamp: new Date().toISOString(),
        sessionId: "session-1",
        prompt: "must-not-enter-service"
      })
    });
    assert.equal(sensitive.status, 400);
    const nestedSensitive = await authorizedFetch(dataDir, `${endpoint}/api/events`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        type: "activity-start",
        timestamp: new Date().toISOString(),
        sessionId: "session-1",
        metadata: { authorization: "must-not-enter-service" }
      })
    });
    assert.equal(nestedSensitive.status, 400);
    assert.equal((await authorizedFetch(dataDir, `${endpoint}/api/health`)).status, 200);
    assert.equal(child.exitCode, null);
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
  const post = (body) => postEvent(dataDir, port, body);

  try {
    await waitForOutput(child.stdout, /Codex Power Mode HUD/);
    const first = await post({
      type: "activity-start",
      sessionId: "conversation-a",
      sessionSource: "desktop",
      timestamp: new Date(1_000).toISOString(),
      state: { sessionId: "conversation-a", sessionSource: "desktop", phase: "act", status: "working", momentum: 2 }
    });
    const second = await post({
      type: "activity-start",
      sessionId: "conversation-b",
      sessionSource: "desktop",
      timestamp: new Date(2_000).toISOString(),
      state: { sessionId: "conversation-b", sessionSource: "desktop", phase: "act", status: "working", momentum: 99 }
    });

    assert.equal((await first.json()).displayed, true);
    assert.equal((await second.json()).displayed, false);

    const state = await (await authorizedFetch(dataDir, `http://127.0.0.1:${port}/api/state`)).json();
    const health = await (await authorizedFetch(dataDir, `http://127.0.0.1:${port}/api/health`)).json();
    assert.equal(state.sessionId, "conversation-a");
    assert.equal(state.momentum, 2);
    assert.equal(health.activity.realEventsReceived, 2);
    assert.equal(health.session.activeSessionId, "conversation-a");
    assert.equal(health.session.activeSessionSource, "desktop");
    assert.equal(health.session.suppressedEvents, 1);

    await mkdir(path.join(dataDir, "native"), { recursive: true });
    await writeFile(path.join(dataDir, "native", "overlay-config.json"), JSON.stringify({ activitySource: "global" }));
    const global = await post({
      type: "activity-start",
      sessionId: "conversation-b",
      sessionSource: "desktop",
      timestamp: new Date(3_000).toISOString(),
      state: { sessionId: "conversation-b", sessionSource: "desktop", phase: "act", status: "working", momentum: 4 }
    });
    const globalDecision = await global.json();
    assert.equal(globalDecision.displayed, true);
    assert.deepEqual(globalDecision.sessionTransition, {
      previousSessionId: "conversation-a",
      currentSessionId: "conversation-b"
    });

    const globalState = await (await authorizedFetch(dataDir, `http://127.0.0.1:${port}/api/state`)).json();
    const globalHealth = await (await authorizedFetch(dataDir, `http://127.0.0.1:${port}/api/health`)).json();
    assert.equal(globalState.sessionId, "conversation-b");
    assert.equal(globalState.momentum, 4);
    assert.equal(globalHealth.activity.realEventsReceived, 3);
    assert.equal(globalHealth.session.activitySource, "global");
    assert.equal(globalHealth.session.activeSessionSource, "desktop");
  } finally {
    child.kill("SIGTERM");
    await waitForExit(child).catch(() => child.kill("SIGKILL"));
    await rm(dataDir, { recursive: true, force: true });
  }
});

test("mix mode streams one shared pool across Codex conversations", async () => {
  const dataDir = await mkdtemp(path.join(os.tmpdir(), "codex-power-mode-server-mix-"));
  const port = await freePort();
  await mkdir(path.join(dataDir, "native"), { recursive: true });
  await writeFile(path.join(dataDir, "native", "overlay-config.json"), JSON.stringify({ activitySource: "mix" }));
  const child = spawn(process.execPath, [path.join(root, "scripts/server.mjs"), "--port", String(port), "--data-dir", dataDir], {
    cwd: root,
    stdio: ["ignore", "pipe", "pipe"]
  });
  try {
    await waitForOutput(child.stdout, /Codex Power Mode HUD/);
    const first = await postEvent(dataDir, port, {
      type: "activity-start", phase: "observe", toolGroup: "search",
      sessionId: "conversation-a", sessionSource: "desktop", timestamp: new Date(1_000).toISOString(),
      state: { sessionId: "conversation-a", phase: "observe", momentum: 14 }
    });
    const second = await postEvent(dataDir, port, {
      type: "activity-start", phase: "act", toolGroup: "change",
      sessionId: "conversation-b", sessionSource: "desktop", timestamp: new Date(2_000).toISOString(),
      state: { sessionId: "conversation-b", phase: "act", momentum: 28 }
    });
    assert.equal((await first.json()).mixed, true);
    assert.equal((await second.json()).mixed, true);
    const state = await (await authorizedFetch(dataDir, `http://127.0.0.1:${port}/api/state`)).json();
    const health = await (await authorizedFetch(dataDir, `http://127.0.0.1:${port}/api/health`)).json();
    assert.equal(state.sessionId, "mix");
    assert.equal(state.momentum, 42);
    assert.equal(state.combo, 2);
    assert.equal(state.mixedConversationCount, 2);
    assert.equal(health.session.activitySource, "mix");
    assert.equal(health.session.activeSessionId, "mix");
  } finally {
    child.kill("SIGTERM");
    await waitForExit(child).catch(() => child.kill("SIGKILL"));
    await rm(dataDir, { recursive: true, force: true });
  }
});

test("typing charge atomically augments the submitted desktop session without prompt text", async () => {
  const dataDir = await mkdtemp(path.join(os.tmpdir(), "codex-power-mode-server-typing-"));
  const port = await freePort();
  const child = spawn(process.execPath, [path.join(root, "scripts/server.mjs"), "--port", String(port), "--data-dir", dataDir], {
    cwd: root,
    stdio: ["ignore", "pipe", "pipe"]
  });
  try {
    await waitForOutput(child.stdout, /Codex Power Mode HUD/);
    await postEvent(dataDir, port, {
      type: "activity-start", phase: "observe", toolGroup: "prompt",
      sessionId: "typing-session", sessionSource: "desktop", timestamp: new Date(1_000).toISOString(),
      state: { sessionId: "typing-session", sessionSource: "desktop", phase: "observe", status: "working", momentum: 14 }
    });
    const response = await authorizedFetch(dataDir, `http://127.0.0.1:${port}/api/typing-charge`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ sessionId: "typing-session", inputCombo: 10 })
    });
    assert.equal(response.status, 202);
    const state = await (await authorizedFetch(dataDir, `http://127.0.0.1:${port}/api/state`)).json();
    const health = await (await authorizedFetch(dataDir, `http://127.0.0.1:${port}/api/health`)).json();
    const history = await readFile(path.join(dataDir, "events.ndjson"), "utf8");
    assert.equal(state.momentum, 46);
    assert.equal(state.combo, 0);
    assert.equal(health.activity.realEventsReceived, 1);
    assert.match(history, /"inputCombo":10/);
    assert.doesNotMatch(history, /prompt|command|code|patch/i);
  } finally {
    child.kill("SIGTERM");
    await waitForExit(child).catch(() => child.kill("SIGKILL"));
    await rm(dataDir, { recursive: true, force: true });
  }
});

test("transient previews do not alter real state, ownership, or activity diagnostics", async () => {
  const dataDir = await mkdtemp(path.join(os.tmpdir(), "codex-power-mode-preview-"));
  const port = await freePort();
  const child = spawn(process.execPath, [path.join(root, "scripts/server.mjs"), "--port", String(port), "--data-dir", dataDir], {
    cwd: root,
    stdio: ["ignore", "pipe", "pipe"]
  });
  const post = (body) => postEvent(dataDir, port, body);

  try {
    await waitForOutput(child.stdout, /Codex Power Mode HUD/);
    await post({
      type: "activity-start",
      sessionId: "real-task",
      sessionSource: "desktop",
      timestamp: new Date(1_000).toISOString(),
      state: { sessionId: "real-task", sessionSource: "desktop", phase: "act", status: "working", momentum: 7 }
    });
    const previewResponse = await post({
      type: "edit",
      sessionId: "demo",
      preview: true,
      timestamp: new Date(2_000).toISOString(),
      state: { sessionId: "demo", phase: "act", status: "working", momentum: 99 }
    });

    assert.deepEqual(await previewResponse.json(), { accepted: true, displayed: true, preview: true });
    const state = await (await authorizedFetch(dataDir, `http://127.0.0.1:${port}/api/state`)).json();
    const health = await (await authorizedFetch(dataDir, `http://127.0.0.1:${port}/api/health`)).json();
    assert.equal(state.sessionId, "real-task");
    assert.equal(state.momentum, 7);
    assert.equal(health.activity.eventsReceived, 1);
    assert.equal(health.activity.realEventsReceived, 1);
    assert.equal(health.session.activeSessionId, "real-task");
    assert.equal(health.session.suppressedEvents, 0);
  } finally {
    child.kill("SIGTERM");
    await waitForExit(child).catch(() => child.kill("SIGKILL"));
    await rm(dataDir, { recursive: true, force: true });
  }
});
