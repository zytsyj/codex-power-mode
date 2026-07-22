#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import { mkdir, readFile, rename, unlink, writeFile } from "node:fs/promises";
import path from "node:path";
import { buildRcReadiness } from "../src/rc-readiness.mjs";
import { powerModeDataDir } from "../src/paths.mjs";

const root = path.resolve(import.meta.dirname, "..");
const outputIndex = process.argv.indexOf("--output");
const output = path.resolve(outputIndex >= 0 && process.argv[outputIndex + 1]
  ? process.argv[outputIndex + 1]
  : ".power-mode/readiness-rc.json");

async function optionalJson(file) {
  try {
    return JSON.parse(await readFile(file, "utf8"));
  } catch (error) {
    if (error?.code === "ENOENT") return null;
    throw error;
  }
}

async function writeJsonAtomic(file, value) {
  await mkdir(path.dirname(file), { recursive: true });
  const temporary = `${file}.tmp-${process.pid}`;
  try {
    await writeFile(temporary, `${JSON.stringify(value, null, 2)}\n`, { mode: 0o600 });
    await rename(temporary, file);
  } catch (error) {
    await unlink(temporary).catch(() => {});
    throw error;
  }
}

const manifest = JSON.parse(await readFile(path.join(root, ".codex-plugin/plugin.json"), "utf8"));
const statusResult = spawnSync(process.execPath, [path.join(root, "scripts/power-mode.mjs"), "status"], {
  cwd: root,
  encoding: "utf8"
});
const liveStatus = statusResult.status === 0 ? JSON.parse(statusResult.stdout) : null;
const reports = Object.fromEntries(await Promise.all([
  ["security", "security-rc.json"],
  ["archive", "archive-rc.json"],
  ["performance", "performance-rc.json"],
  ["stability", "stability-rc.json"],
  ["compatibility", "compatibility-rc.json"]
].map(async ([name, filename]) => [name, await optionalJson(path.join(root, ".power-mode", filename))])));
const interactionSession = await optionalJson(path.join(powerModeDataDir(), "acceptance", "interaction-rc.json"));
const report = buildRcReadiness({ currentVersion: manifest.version, reports, liveStatus, interactionSession });
await writeJsonAtomic(output, report);

if (process.argv.includes("--json")) {
  process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
} else {
  const lines = [
    `Power Mode RC: ${report.status}`,
    ...report.automatic.map((gate) => `[${gate.status.toUpperCase()}] ${gate.name}`),
    `[${report.realHook.status.toUpperCase()}] trusted Codex Hook`,
    `[${report.interaction.status.toUpperCase()}] hands-on interaction (${report.interaction.counts.passed} passed, ${report.interaction.counts.pending} pending)`,
    `[${report.instruments.status.toUpperCase()}] Instruments GPU/Energy Log`,
    `${report.ownerDecisions.length} owner decisions remain`,
    `${report.blockers.length} total blockers; no publication action was taken`
  ];
  process.stdout.write(`${lines.join("\n")}\n`);
}
