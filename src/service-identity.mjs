import { readFile } from "node:fs/promises";
import path from "node:path";

export async function pluginIdentity(root) {
  const manifest = JSON.parse(await readFile(path.join(root, ".codex-plugin/plugin.json"), "utf8"));
  return { version: manifest.version, root: path.resolve(root) };
}

export function serviceMatchesPlugin(health, identity) {
  return health?.serviceVersion === identity.version &&
    typeof health?.serviceRoot === "string" &&
    path.resolve(health.serviceRoot) === identity.root;
}

export function isPowerModeServerCommand(command) {
  const value = String(command || "");
  return /codex-power-mode/.test(value) && /scripts\/server\.mjs(?:\s|$)/.test(value);
}
