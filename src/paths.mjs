import os from "node:os";
import path from "node:path";

export function powerModeDataDir(environment = process.env, homeDirectory = os.homedir()) {
  const configured = environment.PLUGIN_DATA || environment.CODEX_POWER_MODE_DATA;
  return path.resolve(configured || path.join(homeDirectory, ".codex", "power-mode"));
}
