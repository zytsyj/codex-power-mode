import { cp, lstat, mkdir, readFile, readdir, readlink, rename, stat, symlink, unlink } from "node:fs/promises";
import path from "node:path";

export const hookRuntimeRetention = 8;

export function planHookRuntimeRetention(entries, currentVersion, retention = hookRuntimeRetention) {
  if (!Number.isInteger(retention) || retention < 1) throw new Error("Hook runtime retention must be a positive integer");
  const normalized = entries.map((entry) => ({ name: String(entry.name), mtimeMs: Number(entry.mtimeMs) || 0 }));
  const names = new Set(normalized.map((entry) => entry.name));
  if (names.size !== normalized.length) throw new Error("Hook runtime entries must have unique names");
  const newest = [...normalized].sort((left, right) => right.mtimeMs - left.mtimeMs || right.name.localeCompare(left.name));
  const protectedNames = new Set(newest.slice(0, retention).map((entry) => entry.name));
  if (currentVersion && names.has(currentVersion)) protectedNames.add(currentVersion);
  return {
    keep: newest.filter((entry) => protectedNames.has(entry.name)).map((entry) => entry.name),
    eligible: newest.filter((entry) => !protectedNames.has(entry.name)).map((entry) => entry.name)
  };
}

async function directoryBytes(directory) {
  let total = 0;
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const entryPath = path.join(directory, entry.name);
    if (entry.isDirectory()) total += await directoryBytes(entryPath);
    else if (entry.isFile()) total += (await stat(entryPath)).size;
  }
  return total;
}

export async function auditHookRuntimes(dataDir, retention = hookRuntimeRetention) {
  const runtimesDir = path.join(dataDir, "hook-runtimes");
  const currentLink = path.join(dataDir, "hook-runtime");
  const directoryEntries = await readdir(runtimesDir, { withFileTypes: true }).catch((error) => {
    if (error?.code === "ENOENT") return [];
    throw error;
  });
  const entries = [];
  for (const entry of directoryEntries) {
    if (!entry.isDirectory()) continue;
    const entryPath = path.join(runtimesDir, entry.name);
    const info = await stat(entryPath);
    entries.push({ name: entry.name, mtimeMs: info.mtimeMs, bytes: await directoryBytes(entryPath) });
  }

  let currentVersion = null;
  try {
    const target = path.resolve(dataDir, await readlink(currentLink));
    if (path.dirname(target) === runtimesDir) currentVersion = path.basename(target);
  } catch (error) {
    if (error?.code !== "ENOENT" && error?.code !== "EINVAL") throw error;
  }
  const plan = planHookRuntimeRetention(entries, currentVersion, retention);
  return {
    schemaVersion: 1,
    mode: "audit-only",
    retention,
    currentVersion,
    runtimeCount: entries.length,
    totalBytes: entries.reduce((sum, entry) => sum + entry.bytes, 0),
    keepCount: plan.keep.length,
    eligibleCount: plan.eligible.length,
    keep: plan.keep,
    eligible: plan.eligible
  };
}

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
