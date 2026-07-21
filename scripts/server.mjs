#!/usr/bin/env node
import http from "node:http";
import { readFile, stat } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { servicePortFromEnvironment } from "../src/config.mjs";
import { createActivityTracker } from "../src/activity.mjs";
import { powerModeDataDir } from "../src/paths.mjs";
import { pluginIdentity } from "../src/service-identity.mjs";
import { createSessionArbiter } from "../src/session-arbiter.mjs";
import { readState, writeStateSnapshot } from "../src/storage.mjs";

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
const clients = new Set();
const activity = createActivityTracker();
const sessionArbiter = createSessionArbiter(await readState(dataDir));

const mime = new Map([
  [".html", "text/html; charset=utf-8"],
  [".css", "text/css; charset=utf-8"],
  [".js", "text/javascript; charset=utf-8"],
  [".svg", "image/svg+xml"]
]);

function sendJson(response, status, body) {
  response.writeHead(status, { "content-type": "application/json", "cache-control": "no-store" });
  response.end(JSON.stringify(body));
}

async function readBody(request) {
  const chunks = [];
  for await (const chunk of request) {
    chunks.push(chunk);
    if (Buffer.concat(chunks).length > 1_000_000) throw new Error("Payload too large");
  }
  return JSON.parse(Buffer.concat(chunks).toString("utf8") || "{}");
}

function broadcast(event) {
  const frame = `data: ${JSON.stringify(event)}\n\n`;
  for (const client of clients) client.write(frame);
}

const server = http.createServer(async (request, response) => {
  const url = new URL(request.url, `http://${request.headers.host || "127.0.0.1"}`);
  if (url.pathname === "/api/health") {
    return sendJson(response, 200, {
      ok: true,
      port,
      dataDir,
      clients: clients.size,
      activity: activity.snapshot(),
      session: sessionArbiter.snapshot(),
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
      connection: "keep-alive",
      "access-control-allow-origin": "*"
    });
    response.write(`data: ${JSON.stringify({ type: "connected", state: await readState(dataDir) })}\n\n`);
    clients.add(response);
    request.on("close", () => clients.delete(response));
    return;
  }
  if (url.pathname === "/api/events" && request.method === "POST") {
    const event = await readBody(request);
    activity.record(event);
    const decision = sessionArbiter.consider(event);
    if (decision.displayed) {
      if (event.state) await writeStateSnapshot(dataDir, event.state);
      broadcast(event);
    }
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
    response.writeHead(200, { "content-type": mime.get(path.extname(filePath)) || "application/octet-stream" });
    response.end(await readFile(filePath));
  } catch {
    sendJson(response, 404, { error: "Not found" });
  }
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
