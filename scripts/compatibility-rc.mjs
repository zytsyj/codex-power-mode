#!/usr/bin/env node
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdir, readFile, readdir, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import process from "node:process";

const root = path.resolve(import.meta.dirname, "..");
const valueAfter = (flag, fallback) => {
  const index = process.argv.indexOf(flag);
  return index >= 0 && process.argv[index + 1] ? process.argv[index + 1] : fallback;
};
const output = path.resolve(valueAfter("--output", ".power-mode/compatibility-rc.json"));
const frames = path.resolve(valueAfter("--frames", ".power-mode/compatibility-render"));

function run(command, args, options = {}) {
  const result = spawnSync(command, args, { cwd: root, encoding: "utf8", ...options });
  if (result.status !== 0) throw new Error(result.stderr || result.stdout || `${command} failed`);
  return result.stdout;
}

function controlStatus(script, cwd) {
  return JSON.parse(run(process.execPath, [script, "status"], { cwd }));
}

function includesEvery(values, expected) {
  return expected.every((item) => values.some((value) => value.includes(item)));
}

if (process.platform !== "darwin") throw new Error("RC compatibility rendering currently requires macOS");
run(process.execPath, [path.join(root, "scripts", "render-qa.mjs"), "--output", frames]);

const filenames = (await readdir(frames)).filter((filename) => filename.endsWith(".png")).sort();
assert.equal(filenames.length, 228, `Expected 228 native QA frames, found ${filenames.length}`);
const dimensions = new Set();
for (const filename of filenames) {
  const bytes = await readFile(path.join(frames, filename));
  assert.deepEqual([...bytes.subarray(0, 8)], [137, 80, 78, 71, 13, 10, 26, 10], `${filename} is not a PNG`);
  const width = bytes.readUInt32BE(16);
  const height = bytes.readUInt32BE(20);
  assert.ok(width > 0 && height > 0, `${filename} has invalid dimensions`);
  dimensions.add(`${width}x${height}`);
}

assert.ok(includesEvery(filenames, ["focus-light", "focus-dark", "arcade-light", "arcade-dark", "reduced-light", "reduced-dark"]));
assert.ok(includesEvery(filenames, ["-observe-", "-act-", "-verify-", "-wait-", "-recover-", "-complete-"]));
assert.ok(includesEvery(filenames, ["-90.png", "-320.png", "-580.png", "-850.png", "-999.png"]));
assert.ok(includesEvery(filenames, ["-verified.png", "-unverified.png", "-cancelled.png", "-no-change.png"]));
assert.ok(includesEvery(filenames, ["cursor-focus-light-spark", "cursor-focus-dark-neon", "cursor-arcade-light-neon-milestone"]));
assert.ok(includesEvery(filenames, ["typing-focus-light-cyan", "typing-arcade-dark-gold", "typing-reduced-dark-violet"]));

const sourceControl = path.join(root, "scripts", "power-mode.mjs");
const status = controlStatus(sourceControl, root);
const controlRoot = status.service?.serviceRoot;
const controlScript = controlRoot ? path.join(controlRoot, "scripts", "power-mode.mjs") : sourceControl;
const doctor = JSON.parse(run(process.execPath, [controlScript, "doctor", "--json"], { cwd: controlRoot || root }));
const doctorChecks = Object.fromEntries(doctor.checks.map((check) => [check.id, check.level]));
const realEventsReceived = status.service?.activity?.realEventsReceived ?? 0;

const report = {
  schemaVersion: 1,
  generatedAt: new Date().toISOString(),
  environment: {
    platform: `${os.platform()} ${os.release()}`,
    architecture: os.arch(),
    pluginVersion: status.service?.serviceVersion ?? null
  },
  automated: {
    passed: true,
    nativeFrames: filenames.length,
    dimensions: [...dimensions].sort(),
    themes: ["light", "dark"],
    motionProfiles: ["focus", "arcade", "reduced-motion"],
    semanticStates: ["observe", "act", "verify", "wait", "recover", "complete"],
    energyTiers: ["wake", "charge", "drive", "critical", "peak"],
    completionOutcomes: ["verified", "unverified", "cancelled", "no-change"],
    cursorSamples: ["spark", "neon", "neon-milestone"],
    typingComboPalettes: ["cyan", "violet", "pink", "gold"],
    serviceHealthy: doctorChecks.service === "ok",
    hudConnected: doctorChecks["hud-connection"] === "ok",
    accessibilityGranted: doctorChecks.accessibility === "ok",
    oneService: doctorChecks["service-instance"] === "ok",
    oneHud: doctorChecks["native-instance"] === "ok"
  },
  realLifecycle: {
    status: realEventsReceived > 0 ? "observed-since-service-start" : "pending-new-trusted-task",
    realEventsReceived
  },
  manualPending: [
    "Spark and Neon tracking the real Codex insertion point",
    "Typing Combo injection from a real UserPromptSubmit",
    "dragging and saved position across restart",
    "multiple-display attach, detach, and visible-frame changes",
    "inactive-app hide, stay-over-Codex, and follow policies",
    "Idle hide and quiet-orb timing",
    "English, Chinese, and automatic language selection",
    "clean install, upgrade, stop, and uninstall on the final support range"
  ],
  privacy: "Synthetic frames and aggregate health only; no task identifiers, prompts, code, commands, key values, cursor coordinates, tokens, or local paths are written to this report"
};

await mkdir(path.dirname(output), { recursive: true });
await writeFile(output, `${JSON.stringify(report, null, 2)}\n`, { mode: 0o600 });
process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
