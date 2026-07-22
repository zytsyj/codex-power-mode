#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import { mkdir, readFile, rename, unlink, writeFile } from "node:fs/promises";
import path from "node:path";
import {
  createInteractionSession,
  recordInteractionResult,
  restoreInteractionSession,
  summarizeInteractionSession
} from "../src/interaction-acceptance.mjs";
import { powerModeDataDir } from "../src/paths.mjs";

const root = path.resolve(import.meta.dirname, "..");
const dataDir = powerModeDataDir();
const reportPath = path.join(dataDir, "acceptance", "interaction-rc.json");
const sourceController = path.join(root, "scripts", "power-mode.mjs");
const command = process.argv[2] || "status";
const jsonOutput = process.argv.includes("--json");

function runController(controller, args) {
  const result = spawnSync(process.execPath, [controller, ...args], { cwd: path.dirname(controller), encoding: "utf8" });
  if (result.status !== 0) throw new Error(result.stderr || result.stdout || `Power Mode ${args[0]} failed`);
  return result.stdout;
}

function currentStatus(controller = sourceController) {
  return JSON.parse(runController(controller, ["status"]));
}

async function readSession() {
  return JSON.parse(await readFile(reportPath, "utf8"));
}

async function writeJSONAtomic(destination, value) {
  await mkdir(path.dirname(destination), { recursive: true });
  const temporary = `${destination}.tmp-${process.pid}`;
  try {
    await writeFile(temporary, `${JSON.stringify(value, null, 2)}\n`, { mode: 0o600 });
    await rename(temporary, destination);
  } catch (error) {
    await unlink(temporary).catch(() => {});
    throw error;
  }
}

function renderSummary(session) {
  const summary = summarizeInteractionSession(session);
  const lines = [
    `Interaction RC: ${summary.status}`,
    `Version: ${summary.pluginVersion}`,
    `Passed ${summary.counts.passed} · Failed ${summary.counts.failed} · Pending ${summary.counts.pending} · Unavailable ${summary.counts.unavailable}`
  ];
  for (const check of summary.checks) lines.push(`[${check.status.toUpperCase()}] ${check.id}: ${check.title}`);
  return `${lines.join("\n")}\n`;
}

if (command === "begin") {
  const previous = await readSession().catch((error) => error?.code === "ENOENT" ? null : Promise.reject(error));
  if (previous?.status === "active") throw new Error("An interaction RC session is already active; resume it or restore settings first");
  const status = currentStatus();
  if (!status.service?.ok || !status.nativeOverlay?.running || !status.nativeOverlay?.configuration) {
    throw new Error("Power Mode service and native HUD must be healthy before beginning interaction acceptance");
  }
  const session = createInteractionSession(status.nativeOverlay.configuration, status.service.serviceVersion);
  await writeJSONAtomic(reportPath, session);
  process.stdout.write(jsonOutput ? `${JSON.stringify(summarizeInteractionSession(session), null, 2)}\n` : renderSummary(session));
} else if (command === "record") {
  const checkId = process.argv[3];
  const result = process.argv[4];
  const session = recordInteractionResult(await readSession(), checkId, result);
  await writeJSONAtomic(reportPath, session);
  process.stdout.write(jsonOutput ? `${JSON.stringify(summarizeInteractionSession(session), null, 2)}\n` : renderSummary(session));
} else if (command === "restore") {
  const session = await readSession();
  const restored = restoreInteractionSession(session);
  const status = currentStatus();
  const controller = path.join(status.service?.serviceRoot || "", "scripts", "power-mode.mjs");
  const manifest = JSON.parse(await readFile(path.join(status.service?.serviceRoot || "", ".codex-plugin", "plugin.json"), "utf8"));
  if (manifest.name !== "codex-power-mode") throw new Error("The running service does not identify an installed Codex Power Mode controller");
  const configPath = path.join(dataDir, "native", "overlay-config.json");
  runController(controller, ["native-stop"]);
  try {
    await writeJSONAtomic(configPath, restored.baselineConfiguration);
  } catch (error) {
    runController(controller, ["native"]);
    throw error;
  }
  runController(controller, ["native"]);
  const restoredStatus = currentStatus(controller);
  if (JSON.stringify(restoredStatus.nativeOverlay?.configuration) !== JSON.stringify(restored.baselineConfiguration)) {
    throw new Error("Power Mode restarted but the baseline settings were not restored exactly");
  }
  await writeJSONAtomic(reportPath, restored);
  process.stdout.write(jsonOutput ? `${JSON.stringify(summarizeInteractionSession(restored), null, 2)}\n` : renderSummary(restored));
} else if (command === "status") {
  const session = await readSession();
  process.stdout.write(jsonOutput ? `${JSON.stringify(summarizeInteractionSession(session), null, 2)}\n` : renderSummary(session));
} else {
  throw new Error("Usage: interaction-rc.mjs <begin|status|record CHECK_ID passed|failed|unavailable|restore> [--json]");
}
