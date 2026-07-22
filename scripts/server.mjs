#!/usr/bin/env node
import http from "node:http";
import { randomBytes } from "node:crypto";
import { readFile, stat } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { servicePortFromEnvironment } from "../src/config.mjs";
import { createActivityTracker } from "../src/activity.mjs";
import { ensureServiceToken, isTrustedBrowserOrigin, requestHasServiceToken } from "../src/auth.mjs";
import { validateIncomingEvent } from "../src/event-validation.mjs";
import { powerModeDataDir } from "../src/paths.mjs";
import { pluginIdentity } from "../src/service-identity.mjs";
import { createSessionArbiter } from "../src/session-arbiter.mjs";
import { readSessionState, readState, recordMixedEventResult, recordSessionEventResult, writeStateSnapshot } from "../src/storage.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const identity = await pluginIdentity(root);
const overlayDir = path.join(root, "overlay");
const args = process.argv.slice(2);
const valueAfter = (flag, fallback) => {
  const index = args.indexOf(flag);
  return index >= 0 && args[index + 1] ? args[index + 1] : fallback;
};
const port = servicePortFromEnvironment({
  CODEX_POWER_MODE_PORT: valueAfter("--port", process.env.CODEX_POWER_MODE_PORT)
});
const dataDir = path.resolve(valueAfter("--data-dir", powerModeDataDir()));
const endpoint = `http://127.0.0.1:${port}`;
const serviceToken = await ensureServiceToken(dataDir);
const browserStreamToken = randomBytes(32).toString("hex");
const clients = new Set();
const activity = createActivityTracker();
const sessionArbiter = createSessionArbiter(await readState(dataDir));
const nativeConfigFile = path.join(dataDir, "native", "overlay-config.json");

async function processEvent(incoming, { recordActivity = true } = {}) {
  const { state: ignoredState, ...event } = incoming;
  if (recordActivity) activity.record(event);
  const previousSession = sessionArbiter.snapshot().activeSessionId;
  const mode = await activitySource();
  const decision = sessionArbiter.consider(event, { mode });
  const sessionTransition = decision.switched && previousSession && previousSession !== event.sessionId
    ? { previousSessionId: previousSession, currentSessionId: event.sessionId }
    : null;
  if (decision.displayed) {
    const state = mode === "mix"
      ? (await recordMixedEventResult(dataDir, event)).state
      : recordActivity
        ? await readSessionState(dataDir, event.sessionId)
        : (await recordSessionEventResult(dataDir, event)).state;
    await writeStateSnapshot(dataDir, state);
    broadcast({ ...event, state, ...(sessionTransition ? { sessionTransition } : {}) });
  }
  return { ...decision, sessionTransition };
}

async function activitySource() {
  try {
    const settings = JSON.parse(await readFile(nativeConfigFile, "utf8"));
    return ["global", "mix"].includes(settings.activitySource) ? settings.activitySource : "focused";
  } catch {
    return "focused";
  }
}

const mime = new Map([
  [".html", "text/html; charset=utf-8"],
  [".css", "text/css; charset=utf-8"],
  [".js", "text/javascript; charset=utf-8"],
  [".mjs", "text/javascript; charset=utf-8"],
  [".svg", "image/svg+xml"]
]);

function sendJson(response, status, body) {
  response.writeHead(status, { "content-type": "application/json", "cache-control": "no-store" });
  response.end(JSON.stringify(body));
}

async function readBody(request) {
  const chunks = [];
  let size = 0;
  for await (const chunk of request) {
    size += chunk.length;
    if (size > 1_000_000) throw Object.assign(new Error("Payload too large"), { statusCode: 413 });
    chunks.push(chunk);
  }
  try {
    return JSON.parse(Buffer.concat(chunks).toString("utf8") || "{}");
  } catch {
    throw Object.assign(new Error("Invalid JSON"), { statusCode: 400 });
  }
}

function requestHasJsonContentType(request) {
  const contentType = String(request.headers["content-type"] ?? "").toLowerCase();
  return contentType === "application/json" || contentType.startsWith("application/json;");
}

function broadcast(event) {
  const frame = `data: ${JSON.stringify(event)}\n\n`;
  for (const client of clients) client.write(frame);
}

async function handleRequest(request, response) {
  const url = new URL(request.url, `http://${request.headers.host || "127.0.0.1"}`);
  if (url.pathname === "/api/browser-token") {
    if (!isTrustedBrowserOrigin(request, endpoint)) return sendJson(response, 403, { error: "Forbidden" });
    return sendJson(response, 200, { token: browserStreamToken });
  }
  const serviceAuthorized = requestHasServiceToken(request, serviceToken);
  const browserStreamAuthorized = url.pathname === "/api/stream" && requestHasServiceToken(request, browserStreamToken, url);
  if (url.pathname.startsWith("/api/") && !serviceAuthorized && !browserStreamAuthorized) {
    return sendJson(response, 401, { error: "Unauthorized" });
  }
  if (request.headers.origin && request.headers.origin !== endpoint) {
    return sendJson(response, 403, { error: "Forbidden origin" });
  }
  if (url.pathname === "/api/health") {
    return sendJson(response, 200, {
      ok: true,
      port,
      dataDir,
      clients: clients.size,
      activity: activity.snapshot(),
      session: { ...sessionArbiter.snapshot(), activitySource: await activitySource() },
      serviceVersion: identity.version,
      serviceRoot: identity.root,
      servicePid: process.pid
    });
  }
  if (url.pathname === "/api/state") return sendJson(response, 200, await readState(dataDir));
  if (url.pathname === "/api/stream") {
    response.writeHead(200, {
      "content-type": "text/event-stream",
      "cache-control": "no-cache",
      connection: "keep-alive"
    });
    response.write(`data: ${JSON.stringify({ type: "connected", state: await readState(dataDir) })}\n\n`);
    clients.add(response);
    request.on("close", () => clients.delete(response));
    return;
  }
  if (url.pathname === "/api/events" && request.method === "POST") {
    if (!requestHasJsonContentType(request)) return sendJson(response, 415, { error: "JSON content type required" });
    const incoming = await readBody(request);
    const validationError = validateIncomingEvent(incoming);
    if (validationError) return sendJson(response, 400, { error: validationError });
    if (incoming.preview === true) {
      broadcast(incoming);
      return sendJson(response, 202, { accepted: true, displayed: true, preview: true });
    }
    const decision = await processEvent(incoming);
    return sendJson(response, 202, { accepted: true, ...decision });
  }
  if (url.pathname === "/api/typing-charge" && request.method === "POST") {
    if (!requestHasJsonContentType(request)) return sendJson(response, 415, { error: "JSON content type required" });
    const body = await readBody(request);
    const incoming = {
      type: "input-charge",
      id: `typing-${Date.now()}-${randomBytes(4).toString("hex")}`,
      timestamp: new Date().toISOString(),
      sessionId: body.sessionId,
      sessionSource: "desktop",
      inputCombo: body.inputCombo
    };
    const validationError = validateIncomingEvent(incoming);
    if (validationError) return sendJson(response, 400, { error: validationError });
    const decision = await processEvent(incoming, { recordActivity: false });
    return sendJson(response, 202, { accepted: true, ...decision });
  }

  const requested = url.pathname === "/" ? "index.html" : url.pathname.slice(1);
  const filePath = path.resolve(overlayDir, requested);
  if (!filePath.startsWith(`${overlayDir}${path.sep}`) && filePath !== path.join(overlayDir, "index.html")) {
    return sendJson(response, 403, { error: "Forbidden" });
  }
  try {
    const info = await stat(filePath);
    if (!info.isFile()) throw new Error("Not a file");
    response.writeHead(200, {
      "content-type": mime.get(path.extname(filePath)) || "application/octet-stream",
      "cache-control": "no-store"
    });
    response.end(await readFile(filePath));
  } catch {
    sendJson(response, 404, { error: "Not found" });
  }
}

const server = http.createServer((request, response) => {
  handleRequest(request, response).catch((error) => {
    if (response.headersSent) return response.destroy(error);
    sendJson(response, error.statusCode ?? 500, {
      error: error.statusCode ? error.message : "Internal server error"
    });
  });
});

server.listen(port, "127.0.0.1", () => {
  process.stdout.write(`Codex Power Mode HUD: http://127.0.0.1:${port}\n`);
});

let shuttingDown = false;
const shutdown = () => {
  if (shuttingDown) return;
  shuttingDown = true;
  for (const client of clients) client.end();
  clients.clear();
  server.close(() => process.exit(0));
  server.closeAllConnections?.();
  setTimeout(() => process.exit(0), 1_000).unref();
};
process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);
