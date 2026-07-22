import assert from "node:assert/strict";
import { mkdir, mkdtemp, readFile, readdir, realpath, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { auditHookRuntimes, installHookRuntime, planHookRuntimeRetention } from "../src/hook-runtime.mjs";

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

test("hook runtime retention keeps the newest eight and always protects the linked current version", () => {
  const entries = Array.from({ length: 12 }, (_, index) => ({ name: `version-${index}`, mtimeMs: index }));
  const plan = planHookRuntimeRetention(entries, "version-1", 8);

  assert.deepEqual(plan.keep, ["version-11", "version-10", "version-9", "version-8", "version-7", "version-6", "version-5", "version-4", "version-1"]);
  assert.deepEqual(plan.eligible, ["version-3", "version-2", "version-0"]);
});

test("hook runtime audit is read-only and reports a bounded cleanup candidate", async () => {
  const temporary = await mkdtemp(path.join(os.tmpdir(), "power-mode-hook-audit-"));
  const dataDir = path.join(temporary, "data");
  for (let index = 0; index < 10; index += 1) {
    const plugin = path.join(temporary, `plugin-${index}`);
    await fixture(plugin, `version-${index}`);
    await installHookRuntime(plugin, dataDir, `version-${index}`);
  }

  const report = await auditHookRuntimes(dataDir, 8);
  assert.equal(report.mode, "audit-only");
  assert.equal(report.currentVersion, "version-9");
  assert.equal(report.runtimeCount, 10);
  assert.equal(report.keepCount, 8);
  assert.equal(report.eligibleCount, 2);
  assert.ok(report.totalBytes > 0);
  assert.equal((await readdir(path.join(dataDir, "hook-runtimes"))).length, 10);
});
