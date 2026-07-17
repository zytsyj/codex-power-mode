#!/usr/bin/env node
import { spawn } from "node:child_process";
import path from "node:path";

const pluginRoot = process.env.PLUGIN_ROOT || path.resolve(new URL("..", import.meta.url).pathname);
const dataDir = process.env.PLUGIN_DATA || path.join(pluginRoot, ".power-mode");

try {
  const response = await fetch("http://127.0.0.1:4737/api/health", { signal: AbortSignal.timeout(200) });
  if (response.ok) process.exit(0);
} catch {
  const child = spawn(process.execPath, [path.join(pluginRoot, "scripts/server.mjs"), "--data-dir", dataDir], {
    cwd: pluginRoot,
    detached: true,
    stdio: "ignore",
    env: { ...process.env, CODEX_POWER_MODE_DATA: dataDir }
  });
  child.unref();
}
