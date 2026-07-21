import { appendFile, mkdir, open, readFile, readdir, rename, stat, unlink, writeFile } from "node:fs/promises";
import path from "node:path";
import { initialState, reduceState, shouldCoalesceActivity } from "./state.mjs";

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const staleLockAgeMs = 10_000;

function processIsAlive(pid) {
  try {
    process.kill(pid, 0);
    return true;
  } catch (error) {
    return error.code !== "ESRCH";
  }
}

async function reclaimAbandonedLock(lockPath) {
  try {
    const [contents, info] = await Promise.all([readFile(lockPath, "utf8"), stat(lockPath)]);
    if (Date.now() - info.mtimeMs < staleLockAgeMs) return false;

    let ownerPid = null;
    try {
      ownerPid = Number.parseInt(JSON.parse(contents).pid, 10);
    } catch {
      // Older versions created an empty lock, so age is the only usable signal.
    }
    if (Number.isInteger(ownerPid) && ownerPid > 0 && processIsAlive(ownerPid)) return false;

    const current = await stat(lockPath);
    if (current.ino !== info.ino || current.mtimeMs !== info.mtimeMs || current.size !== info.size) return false;
    await unlink(lockPath);
    return true;
  } catch (error) {
    if (error.code === "ENOENT") return true;
    return false;
  }
}

async function withLock(dataDir, operation) {
  const lockPath = path.join(dataDir, "state.lock");
  let handle;
  for (let attempt = 0; attempt < 40; attempt += 1) {
    try {
      handle = await open(lockPath, "wx");
      break;
    } catch (error) {
      if (error.code !== "EEXIST") throw error;
      if (await reclaimAbandonedLock(lockPath)) continue;
      await sleep(10 + attempt * 2);
    }
  }
  if (!handle) throw new Error("Could not acquire Power Mode state lock");
  try {
    await handle.writeFile(JSON.stringify({ pid: process.pid, acquiredAt: new Date().toISOString() }));
    return await operation();
  } finally {
    await handle.close();
    await unlink(lockPath).catch(() => {});
  }
}

export async function readState(dataDir) {
  try {
    const stored = JSON.parse(await readFile(path.join(dataDir, "state.json"), "utf8"));
    if (stored.sessionId === "demo") return readLatestRealSessionState(dataDir);
    const { score: _legacyScore, mode: _legacyMode, ...current } = stored;
    const state = { ...initialState, ...current };
    if (!Object.hasOwn(stored, "comboStatus")) {
      state.combo = 0;
      state.bestCombo = 0;
      state.comboBreaks = 0;
      state.comboStatus = "idle";
      state.comboLastAt = null;
      state.comboHoldUntil = null;
      state.comboExpiresAt = null;
      state.comboBrokenAt = null;
    }
    return state;
  } catch (error) {
    if (error.code === "ENOENT") return { ...initialState };
    throw error;
  }
}

function stateActivityTime(state) {
  return Math.max(0, ...[
    Date.parse(state.turnStoppedAt),
    Date.parse(state.lastVerificationAt),
    Date.parse(state.lastEditAt),
    Date.parse(state.lastActivityAt)
  ].filter(Number.isFinite));
}

async function readLatestRealSessionState(dataDir) {
  const sessionsDir = path.join(dataDir, "sessions");
  let entries;
  try {
    entries = await readdir(sessionsDir, { withFileTypes: true });
  } catch (error) {
    if (error.code === "ENOENT") return { ...initialState };
    throw error;
  }
  const states = await Promise.all(entries
    .filter((entry) => entry.isFile() && entry.name.endsWith(".json"))
    .map((entry) => readStateFile(path.join(sessionsDir, entry.name)).catch(() => null)));
  return states
    .filter((state) => state?.sessionId && state.sessionId !== "demo")
    .sort((left, right) => stateActivityTime(right) - stateActivityTime(left))[0] ?? { ...initialState };
}

async function writeStateFile(dataDir, state) {
  const temp = path.join(dataDir, `state-${process.pid}.tmp`);
  await writeFile(temp, JSON.stringify(state, null, 2));
  await rename(temp, path.join(dataDir, "state.json"));
}

function sessionStatePath(dataDir, sessionId) {
  const safeSessionId = String(sessionId || "unknown").replace(/[^a-zA-Z0-9._-]/g, "_");
  return path.join(dataDir, "sessions", `${safeSessionId}.json`);
}

async function readStateFile(filePath) {
  try {
    const stored = JSON.parse(await readFile(filePath, "utf8"));
    const { score: _legacyScore, mode: _legacyMode, ...current } = stored;
    return { ...initialState, ...current };
  } catch (error) {
    if (error.code === "ENOENT") return { ...initialState };
    throw error;
  }
}

async function writeSessionStateFile(dataDir, sessionId, state) {
  const sessionsDir = path.join(dataDir, "sessions");
  await mkdir(sessionsDir, { recursive: true });
  const target = sessionStatePath(dataDir, sessionId);
  const temp = path.join(sessionsDir, `${path.basename(target)}-${process.pid}.tmp`);
  await writeFile(temp, JSON.stringify(state, null, 2));
  await rename(temp, target);
}

export async function readSessionState(dataDir, sessionId) {
  return readStateFile(sessionStatePath(dataDir, sessionId));
}

export async function writeStateSnapshot(dataDir, state) {
  if (!state || typeof state !== "object" || Array.isArray(state)) throw new TypeError("Power Mode state must be an object");
  await mkdir(dataDir, { recursive: true });
  return withLock(dataDir, async () => {
    await writeStateFile(dataDir, state);
    return state;
  });
}

export async function recordEventResult(dataDir, event, { coalesceWindowMs = 0 } = {}) {
  await mkdir(dataDir, { recursive: true });
  return withLock(dataDir, async () => {
    const previous = await readState(dataDir);
    if (shouldCoalesceActivity(previous, event, coalesceWindowMs)) {
      return { state: previous, recorded: false };
    }
    const next = reduceState(previous, event);
    await appendFile(path.join(dataDir, "events.ndjson"), `${JSON.stringify({ ...event, state: next })}\n`);
    await writeStateFile(dataDir, next);
    return { state: next, recorded: true };
  });
}

export async function recordSessionEventResult(dataDir, event, { coalesceWindowMs = 0 } = {}) {
  await mkdir(dataDir, { recursive: true });
  return withLock(dataDir, async () => {
    const previous = await readSessionState(dataDir, event.sessionId);
    if (shouldCoalesceActivity(previous, event, coalesceWindowMs)) {
      return { state: previous, recorded: false };
    }
    const next = reduceState(previous, event);
    await appendFile(path.join(dataDir, "events.ndjson"), `${JSON.stringify({ ...event, state: next })}\n`);
    await writeSessionStateFile(dataDir, event.sessionId, next);
    return { state: next, recorded: true };
  });
}

export async function recordEvent(dataDir, event) {
  return (await recordEventResult(dataDir, event)).state;
}
