#!/usr/bin/env node
import { eventFromHook } from "../src/events.mjs";
import { powerModeDataDir } from "../src/paths.mjs";
import { recordEventResult } from "../src/storage.mjs";

async function readStdin() {
  const chunks = [];
  for await (const chunk of process.stdin) chunks.push(chunk);
  return JSON.parse(Buffer.concat(chunks).toString("utf8") || "{}");
}

async function notifyServer(event, state) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 250);
  try {
    await fetch("http://127.0.0.1:4737/api/events", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ ...event, state }),
      signal: controller.signal
    });
  } catch {
    // The HUD is optional; events remain persisted for its next launch.
  } finally {
    clearTimeout(timeout);
  }
}

try {
  const input = await readStdin();
  const event = eventFromHook(input);
  if (event) {
    const dataDir = powerModeDataDir();
    const configuredWindow = Number.parseInt(process.env.CODEX_POWER_MODE_OBSERVE_THROTTLE_MS || "900", 10);
    const coalesceWindowMs = Number.isFinite(configuredWindow) ? Math.max(0, Math.min(5_000, configuredWindow)) : 900;
    const result = await recordEventResult(dataDir, event, { coalesceWindowMs });
    if (result.recorded) await notifyServer(event, result.state);
  }
} catch (error) {
  process.stderr.write(`Codex Power Mode hook skipped: ${error.message}\n`);
}
