import { appendFile, mkdir, open, readFile, rename, unlink, writeFile } from "node:fs/promises";
import path from "node:path";
import { initialState, reduceState } from "./state.mjs";

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function withLock(dataDir, operation) {
  const lockPath = path.join(dataDir, "state.lock");
  let handle;
  for (let attempt = 0; attempt < 40; attempt += 1) {
    try {
      handle = await open(lockPath, "wx");
      break;
    } catch (error) {
      if (error.code !== "EEXIST") throw error;
      await sleep(10 + attempt * 2);
    }
  }
  if (!handle) throw new Error("Could not acquire Power Mode state lock");
  try {
    return await operation();
  } finally {
    await handle.close();
    await unlink(lockPath).catch(() => {});
  }
}

export async function readState(dataDir) {
  try {
    return { ...initialState, ...JSON.parse(await readFile(path.join(dataDir, "state.json"), "utf8")) };
  } catch (error) {
    if (error.code === "ENOENT") return { ...initialState };
    throw error;
  }
}

export async function recordEvent(dataDir, event) {
  await mkdir(dataDir, { recursive: true });
  return withLock(dataDir, async () => {
    const next = reduceState(await readState(dataDir), event);
    await appendFile(path.join(dataDir, "events.ndjson"), `${JSON.stringify({ ...event, state: next })}\n`);
    const temp = path.join(dataDir, `state-${process.pid}.tmp`);
    await writeFile(temp, JSON.stringify(next, null, 2));
    await rename(temp, path.join(dataDir, "state.json"));
    return next;
  });
}
