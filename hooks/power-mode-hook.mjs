#!/usr/bin/env node
import { eventFromHook } from "../src/events.mjs";
import { serviceEndpointFromEnvironment } from "../src/config.mjs";
import { powerModeDataDir } from "../src/paths.mjs";
import { sessionSourceFromTranscript, shouldTrackSessionSource } from "../src/session-source.mjs";
import { recordSessionEventResult } from "../src/storage.mjs";

async function readStdin() {
  const chunks = [];
  for await (const chunk of process.stdin) chunks.push(chunk);
  return JSON.parse(Buffer.concat(chunks).toString("utf8") || "{}");
}

async function notifyServer(event, state) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 250);
  try {
    await fetch(`${serviceEndpointFromEnvironment(process.env)}/api/events`, {
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

async function main() {
  const input = await readStdin();
  const sessionSource = await sessionSourceFromTranscript(input.transcript_path);
  if (!shouldTrackSessionSource(sessionSource)) return;
  const event = eventFromHook({ ...input, session_source: sessionSource });
  if (event) {
    const dataDir = powerModeDataDir();
    const configuredWindow = Number.parseInt(process.env.CODEX_POWER_MODE_OBSERVE_THROTTLE_MS || "900", 10);
    const coalesceWindowMs = Number.isFinite(configuredWindow) ? Math.max(0, Math.min(5_000, configuredWindow)) : 900;
    const result = await recordSessionEventResult(dataDir, event, { coalesceWindowMs });
    if (result.recorded) await notifyServer(event, result.state);
  }
}

try {
  await main();
} catch (error) {
  process.stderr.write(`Codex Power Mode hook skipped: ${error.message}\n`);
}
