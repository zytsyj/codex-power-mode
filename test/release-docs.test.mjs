import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import path from "node:path";
import test from "node:test";

const root = path.resolve(import.meta.dirname, "..");

test("public-release documentation exists while publication remains explicitly blocked", async () => {
  const required = [
    "README.md",
    "SECURITY.md",
    "CONTRIBUTING.md",
    "CODE_OF_CONDUCT.md",
    "docs/ARCHITECTURE.md",
    "docs/PRIVACY.md",
    "docs/RELEASE_CHECKLIST.md"
  ];
  await Promise.all(required.map((filename) => readFile(path.join(root, filename), "utf8")));

  const manifest = JSON.parse(await readFile(path.join(root, ".codex-plugin/plugin.json"), "utf8"));
  const packageManifest = JSON.parse(await readFile(path.join(root, "package.json"), "utf8"));
  const readme = await readFile(path.join(root, "README.md"), "utf8");
  const checklist = await readFile(path.join(root, "docs/RELEASE_CHECKLIST.md"), "utf8");
  assert.equal(manifest.license, "UNLICENSED");
  assert.equal(packageManifest.private, true);
  assert.match(readme, /not open source yet/);
  assert.match(checklist, /Choose and approve an open-source license/);
  assert.match(checklist, /owner explicitly authorizes publication/);
});
