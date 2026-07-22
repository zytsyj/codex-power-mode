import assert from "node:assert/strict";
import { mkdtemp, readFile, rm, stat } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { ensureServiceToken, serviceTokenPath } from "../src/auth.mjs";

test("service authentication creates one private installation token", async () => {
  const dataDir = await mkdtemp(path.join(os.tmpdir(), "codex-power-mode-auth-"));
  try {
    const tokens = await Promise.all(Array.from({ length: 8 }, () => ensureServiceToken(dataDir)));
    assert.equal(new Set(tokens).size, 1);
    assert.match(tokens[0], /^[a-f0-9]{64}$/);
    assert.equal((await readFile(serviceTokenPath(dataDir), "utf8")).trim(), tokens[0]);
    assert.equal((await stat(serviceTokenPath(dataDir))).mode & 0o777, 0o600);
  } finally {
    await rm(dataDir, { recursive: true, force: true });
  }
});
