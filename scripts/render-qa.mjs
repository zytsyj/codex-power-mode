#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import process from "node:process";

const outputFlag = process.argv.indexOf("--output");
if (process.platform !== "darwin" || outputFlag < 0 || !process.argv[outputFlag + 1]) {
  process.stderr.write("Usage on macOS: render-qa.mjs --output <directory>\n");
  process.exit(2);
}

const root = path.resolve(import.meta.dirname, "..");
const output = path.resolve(process.argv[outputFlag + 1]);
const buildDir = await mkdtemp(path.join(tmpdir(), "codex-power-mode-render-"));
const binary = path.join(buildDir, "power-mode-render");

function run(command, args, options = {}) {
  const result = spawnSync(command, args, { cwd: root, encoding: "utf8", ...options });
  if (result.stdout) process.stdout.write(result.stdout);
  if (result.stderr) process.stderr.write(result.stderr);
  if (result.status !== 0) process.exitCode = result.status || 1;
  return result.status === 0;
}

try {
  const compiled = run("xcrun", [
    "swiftc", "-swift-version", "5", "-parse-as-library",
    "native/macos/PowerModeOverlay.swift", "-o", binary,
    "-framework", "AppKit", "-framework", "ApplicationServices",
    "-framework", "Foundation", "-framework", "QuartzCore"
  ]);
  if (compiled) {
    run(binary, [], { env: { ...process.env, CODEX_POWER_MODE_RENDER_QA_DIR: output } });
  }
} finally {
  await rm(buildDir, { recursive: true, force: true });
}

if (!process.exitCode) process.stdout.write(`QA frames: ${output}\n`);
