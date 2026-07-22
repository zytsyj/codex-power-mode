import { cp, lstat, mkdir, readFile, rename, symlink, unlink } from "node:fs/promises";
import path from "node:path";

async function removeIfPresent(target) {
  try {
    await lstat(target);
    await unlink(target);
  } catch (error) {
    if (error?.code !== "ENOENT") throw error;
  }
}

export async function pluginVersion(pluginRoot) {
  const manifest = JSON.parse(await readFile(path.join(pluginRoot, ".codex-plugin", "plugin.json"), "utf8"));
  return String(manifest.version || "development").replace(/[^a-zA-Z0-9._+-]/g, "-");
}

export async function installHookRuntime(pluginRoot, dataDir, version = null) {
  const runtimeVersion = version || await pluginVersion(pluginRoot);
  const runtimesDir = path.join(dataDir, "hook-runtimes");
  const versionDir = path.join(runtimesDir, runtimeVersion);
  const currentLink = path.join(dataDir, "hook-runtime");
  const temporaryLink = path.join(dataDir, `.hook-runtime-${process.pid}-${Date.now()}`);

  await mkdir(versionDir, { recursive: true });
  await cp(path.join(pluginRoot, "src"), path.join(versionDir, "src"), { recursive: true, force: true });
  await mkdir(path.join(versionDir, "hooks"), { recursive: true });
  await cp(path.join(pluginRoot, "hooks", "power-mode-hook.mjs"), path.join(versionDir, "hooks", "power-mode-hook.mjs"), { force: true });

  await removeIfPresent(temporaryLink);
  await symlink(path.relative(dataDir, versionDir), temporaryLink, "dir");
  await rename(temporaryLink, currentLink);
  return { currentLink, runtimeVersion, versionDir };
}
