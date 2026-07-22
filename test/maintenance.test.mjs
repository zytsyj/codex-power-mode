import assert from "node:assert/strict";
import { mkdtemp, mkdir, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import { isSafePowerModeDataDir, purgePowerModeData, resetOverlaySettings } from "../src/maintenance.mjs";

test("maintenance refuses broad or unrelated directories", async () => {
  assert.equal(isSafePowerModeDataDir("/"), false);
  assert.equal(isSafePowerModeDataDir("/tmp"), false);
  assert.equal(isSafePowerModeDataDir("/tmp/unrelated"), false);
  await assert.rejects(() => purgePowerModeData("/tmp/unrelated"), /Refusing/);
});

test("settings reset preserves history while purge removes only the recognized data root", async () => {
  const parent = await mkdtemp(path.join(tmpdir(), "power-mode-maintenance-"));
  const dataDir = path.join(parent, "codex-power-mode-personal");
  await mkdir(path.join(dataDir, "native"), { recursive: true });
  await writeFile(path.join(dataDir, "native", "overlay-config.json"), "{}\n");
  await writeFile(path.join(dataDir, "state.json"), "history\n");

  await resetOverlaySettings(dataDir);
  assert.equal(await readFile(path.join(dataDir, "state.json"), "utf8"), "history\n");
  await assert.rejects(() => readFile(path.join(dataDir, "native", "overlay-config.json")), { code: "ENOENT" });

  await purgePowerModeData(dataDir);
  await assert.rejects(() => readFile(path.join(dataDir, "state.json")), { code: "ENOENT" });
});
