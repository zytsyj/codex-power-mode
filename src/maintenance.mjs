import { rm, unlink } from "node:fs/promises";
import path from "node:path";

export function isSafePowerModeDataDir(dataDir) {
  const resolved = path.resolve(dataDir);
  return resolved !== path.parse(resolved).root && ["codex-power-mode-personal", "power-mode"].includes(path.basename(resolved));
}

export async function resetOverlaySettings(dataDir) {
  if (!isSafePowerModeDataDir(dataDir)) throw new Error("Refusing to reset an unrecognized data directory");
  await unlink(path.join(dataDir, "native", "overlay-config.json")).catch((error) => {
    if (error.code !== "ENOENT") throw error;
  });
}

export async function purgePowerModeData(dataDir) {
  if (!isSafePowerModeDataDir(dataDir)) throw new Error("Refusing to remove an unrecognized data directory");
  await rm(dataDir, { recursive: true, force: true });
}
