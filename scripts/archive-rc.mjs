#!/usr/bin/env node
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { execFileSync, spawnSync } from "node:child_process";
import { mkdir, mkdtemp, readFile, rm, stat, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import process from "node:process";

const root = path.resolve(import.meta.dirname, "..");
const outputFlag = process.argv.indexOf("--output");
const output = path.resolve(outputFlag >= 0 && process.argv[outputFlag + 1]
  ? process.argv[outputFlag + 1]
  : ".power-mode/archive-rc.json");
const temporaryRoot = await mkdtemp(path.join(os.tmpdir(), "codex-power-mode-archive-rc-"));
const extractRoot = path.join(temporaryRoot, "extract");

const forbiddenPaths = [
  /(^|\/)\.git(?:\/|$)/,
  /(^|\/)\.power-mode(?:\/|$)/,
  /(^|\/)node_modules(?:\/|$)/,
  /(^|\/)coverage(?:\/|$)/,
  /(^|\/)\.env(?:\.|$)/,
  /(^|\/)\.npmrc$/,
  /(^|\/)\.DS_Store$/,
  /(^|\/)service-token$/,
  /(^|\/)overlay-config\.json$/,
  /(^|\/)state\.json$/,
  /(^|\/)codex-power-mode-overlay$/,
  /\.(?:log|tgz|pem|key|p12|mobileprovision)$/i
];
const personalPathPatterns = [
  /\/Users\/(?!example\/|me\/|tester\/)[A-Za-z0-9._-]+\//,
  /\/home\/(?!example\/|runner\/|tester\/)[A-Za-z0-9._-]+\//
];
const privateKeyPattern = /-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/;
const allowedBinary = /^(?:docs\/media\/[^/]+\.(?:png|gif)|assets\/meme-stickers\/[^/]+\.png)$/;

try {
  const packageManifest = JSON.parse(await readFile(path.join(root, "package.json"), "utf8"));
  const pluginManifest = JSON.parse(await readFile(path.join(root, ".codex-plugin", "plugin.json"), "utf8"));
  assert.equal(packageManifest.private, true, "Source package must remain protected from accidental npm publication");
  assert.equal(pluginManifest.license, "MIT", "Public source archive must declare MIT");
  assert.equal(pluginManifest.repository, "https://github.com/zytsyj/codex-power-mode", "Public repository metadata is missing");
  assert.equal(pluginManifest.homepage, "https://github.com/zytsyj/codex-power-mode", "Public homepage metadata is missing");

  const packed = spawnSync("npm", ["pack", "--json", "--pack-destination", temporaryRoot], {
    cwd: root,
    encoding: "utf8"
  });
  if (packed.status !== 0) throw new Error(packed.stderr || "npm pack failed");
  const packResult = JSON.parse(packed.stdout)[0];
  const archivePath = path.join(temporaryRoot, packResult.filename);
  const archiveBytes = await readFile(archivePath);
  assert.ok(archiveBytes.length < 2_000_000, "RC archive exceeds the 2 MB source-package budget");

  await mkdir(extractRoot, { recursive: true });
  const extracted = spawnSync("tar", ["-xzf", archivePath, "-C", extractRoot], { encoding: "utf8" });
  if (extracted.status !== 0) throw new Error(extracted.stderr || "Could not extract RC archive");

  const tracked = new Set(execFileSync("git", ["ls-files", "-z"], { cwd: root })
    .toString("utf8").split("\0").filter(Boolean));
  const files = packResult.files.map((entry) => entry.path);
  for (const required of [
    ".codex-plugin/plugin.json", "hooks/hooks.json", "hooks/session-start.mjs",
    "hooks/power-mode-hook.mjs", "skills/power-mode/SKILL.md", "native/macos/PowerModeOverlay.swift",
    "scripts/server.mjs", "package.json", "LICENSE", "THIRD_PARTY_NOTICES.md"
  ]) assert.ok(files.includes(required), `RC archive is missing ${required}`);

  for (const filename of files) {
    assert.ok(tracked.has(filename), `Untracked file entered RC archive: ${filename}`);
    assert.equal(forbiddenPaths.some((pattern) => pattern.test(filename)), false, `Forbidden artifact entered RC archive: ${filename}`);
    const bytes = await readFile(path.join(extractRoot, "package", filename));
    if (bytes.includes(0)) {
      assert.match(filename, allowedBinary, `Undeclared binary entered RC archive: ${filename}`);
      continue;
    }
    const text = bytes.toString("utf8");
    assert.equal(personalPathPatterns.some((pattern) => pattern.test(text)), false, `Personal absolute path found in ${filename}`);
    assert.equal(privateKeyPattern.test(text), false, `Private key material found in ${filename}`);
  }

  const media = files.filter((filename) => /\.(?:png|gif)$/i.test(filename));
  assert.ok(media.length > 0, "RC archive must include the documented first-party preview media");
  assert.ok(media.every((filename) => allowedBinary.test(filename)), "Media outside the declared directories is not allowed");
  const mediaDocs = [
    await readFile(path.join(root, "docs", "MEDIA.md"), "utf8"),
    await readFile(path.join(root, "docs", "DEPENDENCIES.md"), "utf8"),
    await readFile(path.join(root, "assets", "meme-stickers", "README.md"), "utf8")
  ].join("\n");
  for (const filename of media) assert.ok(mediaDocs.includes(path.basename(filename)), `Missing provenance for ${filename}`);

  const report = {
    schemaVersion: 1,
    generatedAt: new Date().toISOString(),
    pluginVersion: pluginManifest.version,
    packageVersion: packageManifest.version,
    archive: {
      format: "tgz",
      bytes: archiveBytes.length,
      sha256: createHash("sha256").update(archiveBytes).digest("hex"),
      entries: files.length,
      trackedEntries: files.filter((filename) => tracked.has(filename)).length,
      mediaEntries: media.length,
      retained: false
    },
    checks: {
      npmPublicationProtected: true,
      mitLicensed: true,
      requiredPluginFiles: true,
      trackedFilesOnly: true,
      forbiddenArtifactsAbsent: true,
      personalPathsAbsent: true,
      publicRepositoryMetadataPresent: true,
      privateKeyMaterialAbsent: true,
      binariesLimitedToDeclaredMedia: true,
      mediaProvenanceComplete: true
    },
    published: false,
    passed: true,
    privacy: "The report contains only versions, aggregate counts, size, checksum, and pass/fail facts; the temporary archive is deleted"
  };
  await mkdir(path.dirname(output), { recursive: true });
  await writeFile(output, `${JSON.stringify(report, null, 2)}\n`, { mode: 0o600 });
  process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
} finally {
  await rm(temporaryRoot, { recursive: true, force: true });
}
