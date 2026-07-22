#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import process from "node:process";

const outputFlag = process.argv.indexOf("--output");
if (process.platform !== "darwin" || outputFlag < 0 || !process.argv[outputFlag + 1]) {
  process.stderr.write("Usage on macOS: render-demos.mjs --output <directory>\n");
  process.exit(2);
}

const root = path.resolve(import.meta.dirname, "..");
const output = path.resolve(process.argv[outputFlag + 1]);
const buildDir = await mkdtemp(path.join(tmpdir(), "codex-power-mode-demos-"));
const frames = path.join(buildDir, "frames");
const composer = path.join(buildDir, "compose-demo");

function run(command, args, options = {}) {
  const result = spawnSync(command, args, { cwd: root, encoding: "utf8", ...options });
  if (result.stdout) process.stdout.write(result.stdout);
  if (result.stderr) process.stderr.write(result.stderr);
  if (result.status !== 0) throw new Error(`${command} failed with status ${result.status}`);
}

try {
  run(process.execPath, ["scripts/render-qa.mjs", "--output", frames]);
  run("xcrun", [
    "swiftc", "-swift-version", "5", "scripts/compose-demo.swift", "-o", composer,
    "-framework", "Foundation", "-framework", "ImageIO", "-framework", "UniformTypeIdentifiers"
  ]);
  run(composer, [frames, output]);
} finally {
  await rm(buildDir, { recursive: true, force: true });
}
