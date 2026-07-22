#!/usr/bin/env node
import { spawn, spawnSync } from "node:child_process";
import { mkdir, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import process from "node:process";
import { performanceBudgetChecks, summarizeProcessSamples } from "../src/performance.mjs";

const root = path.resolve(import.meta.dirname, "..");
const outputFlag = process.argv.indexOf("--output");
const output = path.resolve(outputFlag >= 0 && process.argv[outputFlag + 1]
  ? process.argv[outputFlag + 1]
  : ".power-mode/performance-rc.json");
const intervalMs = 500;
const budgets = {
  idleCpuP95: { hud: 5, service: 3 },
  activeCpuP95: { hud: 45, service: 15 },
  maxRssMB: { hud: 128, service: 128 },
  idlePowerScore: { hud: 5, service: 3 },
  activePowerScore: { hud: 50, service: 15 },
  maxThreads: { hud: 20, service: 30 }
};

function control(script, cwd, command, options = {}) {
  const result = spawnSync(process.execPath, [script, command], {
    cwd,
    encoding: "utf8",
    ...options
  });
  if (result.status !== 0) throw new Error(result.stderr || `${command} failed`);
  return result.stdout;
}

function processRows(pids) {
  const result = spawnSync("ps", ["-p", pids.join(","), "-o", "pid=,%cpu=,rss="], { encoding: "utf8" });
  if (result.status !== 0) return [];
  return result.stdout.trim().split(/\r?\n/).filter(Boolean).map((line) => {
    const [pid, cpuPercent, rssKB] = line.trim().split(/\s+/).map(Number);
    return { pid, cpuPercent, rssBytes: rssKB * 1024 };
  });
}

function energyImpactRows(pids) {
  const argumentsList = ["-l", "2", "-s", "1"];
  for (const pid of pids) argumentsList.push("-pid", String(pid));
  argumentsList.push("-stats", "pid,cpu,mem,power,threads,csw,state");
  const result = spawnSync("top", argumentsList, { encoding: "utf8" });
  if (result.status !== 0) return new Map();
  const history = new Map();
  for (const line of result.stdout.split(/\r?\n/)) {
    const columns = line.trim().split(/\s+/);
    const pid = Number(columns[0]);
    if (!pids.includes(pid) || columns.length < 7) continue;
    const samples = history.get(pid) ?? [];
    samples.push({
      powerScore: Number(columns[3]),
      threads: Number(columns[4]),
      contextSwitches: Number.parseFloat(columns[5])
    });
    history.set(pid, samples);
  }
  return new Map([...history].map(([pid, samples]) => {
    const latest = samples.at(-1);
    const previous = samples.at(-2) ?? latest;
    return [pid, {
      powerScore: latest.powerScore,
      threads: latest.threads,
      contextSwitchesPerSecond: Number(Math.max(0, latest.contextSwitches - previous.contextSwitches).toFixed(2))
    }];
  }));
}

async function sampleScenario(name, durationMs, command = null) {
  const samples = { hud: [], service: [] };
  let child = null;
  if (command) {
    child = spawn(process.execPath, [controlScript, command], { cwd: controlRoot || root, stdio: "ignore" });
  }
  const energyImpact = energyImpactRows([hudPid, servicePid]);
  const deadline = Date.now() + durationMs;
  while (Date.now() < deadline) {
    const rows = processRows([hudPid, servicePid]);
    for (const row of rows) {
      if (row.pid === hudPid) samples.hud.push(row);
      if (row.pid === servicePid) samples.service.push(row);
    }
    await new Promise((resolve) => setTimeout(resolve, intervalMs));
  }
  if (child && child.exitCode === null) await new Promise((resolve) => child.once("exit", resolve));
  if (child && child.exitCode !== 0) throw new Error(`${command} preview exited with status ${child.exitCode}`);
  return {
    name,
    durationSeconds: durationMs / 1000,
    hud: { ...summarizeProcessSamples(samples.hud), energyImpact: energyImpact.get(hudPid) ?? null },
    service: { ...summarizeProcessSamples(samples.service), energyImpact: energyImpact.get(servicePid) ?? null }
  };
}

if (process.platform !== "darwin") throw new Error("RC performance sampling currently requires macOS");
const sourceControl = path.join(root, "scripts", "power-mode.mjs");
const before = JSON.parse(control(sourceControl, root, "status"));
const hudPid = before.nativeOverlay?.pid;
const servicePid = before.service?.servicePid;
if (!Number.isInteger(hudPid) || !Number.isInteger(servicePid)) throw new Error("Start one native HUD and service before sampling");
const controlRoot = before.service?.serviceRoot;
const controlScript = controlRoot ? path.join(controlRoot, "scripts", "power-mode.mjs") : sourceControl;

const results = [];
results.push(await sampleScenario("idle", 6_000));
results.push(await sampleScenario("fullShowcase", 24_000, "showcase"));
results.push(await sampleScenario("energyBreakthrough", 11_000, "energy-showcase"));
const scenarios = Object.fromEntries(results.map((result) => [result.name, { hud: result.hud, service: result.service }]));
const checks = performanceBudgetChecks(scenarios, budgets);
const after = JSON.parse(control(controlScript, controlRoot || root, "status"));
if (after.service?.servicePid !== servicePid || after.nativeOverlay?.pid !== hudPid) {
  throw new Error("Power Mode process identity changed during sampling");
}
const report = {
  schemaVersion: 1,
  generatedAt: new Date().toISOString(),
  environment: {
    platform: `${os.platform()} ${os.release()}`,
    architecture: os.arch(),
    node: process.version,
    pluginVersion: after.service?.serviceVersion ?? null,
    preset: after.nativeOverlay?.configuration?.preset ?? null,
    intensity: after.nativeOverlay?.configuration?.effectIntensity ?? null,
    reducedMotion: after.nativeOverlay?.configuration?.reducedMotion ?? null,
    scale: after.nativeOverlay?.configuration?.scale ?? null
  },
  method: {
    intervalMs,
    syntheticPreview: true,
    realStateRestored: true,
    energyImpact: "macOS top POWER score; context switches are a one-second delta",
    gpu: "No direct per-process GPU percentage; Instruments validation remains an RC follow-up"
  },
  budgets,
  scenarios: Object.fromEntries(results.map(({ name, ...result }) => [name, result])),
  checks,
  passed: checks.every((check) => check.pass)
};

await mkdir(path.dirname(output), { recursive: true });
await writeFile(output, `${JSON.stringify(report, null, 2)}\n`, { mode: 0o600 });
process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
if (!report.passed) process.exitCode = 1;
