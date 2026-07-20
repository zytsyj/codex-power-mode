#!/usr/bin/env node
import { spawn } from "node:child_process";
import path from "node:path";
import { startupMode } from "../src/startup.mjs";

const pluginRoot = process.env.PLUGIN_ROOT || path.resolve(new URL("..", import.meta.url).pathname);
const dataDir = process.env.PLUGIN_DATA || path.join(pluginRoot, ".power-mode");

try {
  const child = spawn(process.execPath, [path.join(pluginRoot, "scripts/power-mode.mjs"), startupMode()], {
    cwd: pluginRoot,
    detached: true,
    stdio: "ignore",
    env: { ...process.env, CODEX_POWER_MODE_DATA: dataDir }
  });
  child.unref();
} catch (error) {
  process.stderr.write(`Codex Power Mode could not start: ${error.message}\n`);
}
