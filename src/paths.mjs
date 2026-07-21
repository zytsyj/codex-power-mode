import { existsSync } from "node:fs";
import os from "node:os";
import path from "node:path";

export function powerModeDataDir(environment = process.env, homeDirectory = os.homedir(), directoryExists = existsSync) {
  const configured = environment.PLUGIN_DATA || environment.CODEX_POWER_MODE_DATA;
  if (configured) return path.resolve(configured);

  const installedPluginData = path.join(homeDirectory, ".codex", "plugins", "data", "codex-power-mode-personal");
  if (directoryExists(installedPluginData)) return path.resolve(installedPluginData);
  return path.resolve(path.join(homeDirectory, ".codex", "power-mode"));
}
