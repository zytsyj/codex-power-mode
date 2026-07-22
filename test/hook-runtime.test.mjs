import assert from "node:assert/strict";
import { mkdir, mkdtemp, readFile, realpath, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { installHookRuntime } from "../src/hook-runtime.mjs";

async function fixture(root, marker) {
  await mkdir(path.join(root, "hooks"), { recursive: true });
  await mkdir(path.join(root, "src"), { recursive: true });
  await writeFile(path.join(root, "hooks", "power-mode-hook.mjs"), marker);
  await writeFile(path.join(root, "src", "events.mjs"), marker);
}

test("hook runtime keeps versioned copies and atomically advances the stable path", async () => {
  const temporary = await mkdtemp(path.join(os.tmpdir(), "power-mode-hook-runtime-"));
  const dataDir = path.join(temporary, "data");
  const first = path.join(temporary, "plugin-one");
  const second = path.join(temporary, "plugin-two");
  await fixture(first, "one");
  await fixture(second, "two");

  const installedFirst = await installHookRuntime(first, dataDir, "1.0.0");
  assert.equal(await readFile(path.join(installedFirst.currentLink, "hooks", "power-mode-hook.mjs"), "utf8"), "one");

  const installedSecond = await installHookRuntime(second, dataDir, "2.0.0");
  assert.equal(await readFile(path.join(installedSecond.currentLink, "hooks", "power-mode-hook.mjs"), "utf8"), "two");
  assert.equal(await readFile(path.join(installedFirst.versionDir, "hooks", "power-mode-hook.mjs"), "utf8"), "one");
  assert.equal(await realpath(installedSecond.currentLink), await realpath(installedSecond.versionDir));
});
