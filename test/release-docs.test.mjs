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
    "THIRD_PARTY_NOTICES.md",
    "docs/ARCHITECTURE.md",
    "docs/DEPENDENCIES.md",
    "docs/INSTALLATION.md",
    "docs/MEDIA.md",
    "docs/PERFORMANCE.md",
    "docs/PRIVACY.md",
    "docs/RELEASE_CHECKLIST.md",
    "docs/STABILITY.md",
    "docs/TROUBLESHOOTING.md"
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

test("stability recovery check is explicit, bounded, and privacy-safe", async () => {
  const packageManifest = JSON.parse(await readFile(path.join(root, "package.json"), "utf8"));
  const stability = await readFile(path.join(root, "docs/STABILITY.md"), "utf8");
  const runner = await readFile(path.join(root, "scripts/stability-rc.mjs"), "utf8");

  assert.equal(packageManifest.scripts["stability:rc"], "node scripts/stability-rc.mjs --output .power-mode/stability-rc.json");
  assert.match(stability, /eight concurrent native-start requests/i);
  assert.match(stability, /does not stop Codex/i);
  assert.match(runner, /Refusing to stop an unrecognized service process/);
  assert.match(runner, /No task identifiers, prompts, code, commands, key values, cursor coordinates, tokens, or local paths/);
});

test("performance baseline is reproducible and keeps final GPU acceptance explicit", async () => {
  const packageManifest = JSON.parse(await readFile(path.join(root, "package.json"), "utf8"));
  const performance = await readFile(path.join(root, "docs/PERFORMANCE.md"), "utf8");
  const sampler = await readFile(path.join(root, "scripts/performance-rc.mjs"), "utf8");

  assert.equal(packageManifest.scripts["perf:rc"], "node scripts/performance-rc.mjs --output .power-mode/performance-rc.json");
  assert.match(performance, /synthetic, isolated preview events/i);
  assert.match(performance, /All automated budgets passed/);
  assert.match(performance, /Instruments-based GPU\/energy inspection/);
  assert.match(sampler, /process identity changed during sampling/);
});

test("checked-in media is generated, privacy-safe, and documented", async () => {
  const media = [
    "arcade-dark-act.png",
    "arcade-dark-complete.png",
    "focus-light-verify.png",
    "reduced-light-recover.png",
    "typing-combo-dark.png"
  ];
  const provenance = await readFile(path.join(root, "docs/MEDIA.md"), "utf8");
  const renderer = await readFile(path.join(root, "scripts/render-qa.mjs"), "utf8");
  for (const filename of media) {
    const bytes = await readFile(path.join(root, "docs/media", filename));
    assert.deepEqual([...bytes.subarray(0, 8)], [137, 80, 78, 71, 13, 10, 26, 10]);
    assert.match(provenance, new RegExp(filename.replaceAll(".", "\\.")));
  }
  assert.match(provenance, /no Codex window, prompt, source code, user name, local path, cursor coordinate, or runtime history/i);
  assert.match(renderer, /CODEX_POWER_MODE_RENDER_QA_DIR/);

  for (const filename of ["focus-demo.gif", "arcade-demo.gif"]) {
    const bytes = await readFile(path.join(root, "docs/media", filename));
    assert.equal(bytes.subarray(0, 6).toString("ascii"), "GIF87a");
    assert.ok(bytes.length < 100_000, `${filename} must stay compact`);
    assert.match(provenance, new RegExp(filename.replaceAll(".", "\\.")));
  }
  const demoRenderer = await readFile(path.join(root, "scripts/render-demos.mjs"), "utf8");
  const composer = await readFile(path.join(root, "scripts/compose-demo.swift"), "utf8");
  assert.match(demoRenderer, /scripts\/render-qa\.mjs/);
  assert.match(composer, /UTType\.gif/);
  assert.deepEqual(
    [...composer.matchAll(/^import\s+([A-Za-z0-9_]+)/gm)].map((match) => match[1]).sort(),
    ["Foundation", "ImageIO", "UniformTypeIdentifiers"]
  );
});

test("installation guide preserves the private release and safe maintenance boundaries", async () => {
  const installation = await readFile(path.join(root, "docs/INSTALLATION.md"), "utf8");
  const troubleshooting = await readFile(path.join(root, "docs/TROUBLESHOOTING.md"), "utf8");

  assert.match(installation, /codex plugin add codex-power-mode@personal/);
  assert.match(installation, /Start a new Codex task after installation/);
  assert.match(installation, /reset:settings -- --yes/);
  assert.match(installation, /purge:data -- --yes/);
  assert.match(installation, /codex plugin remove codex-power-mode@personal/);
  assert.match(installation, /public installation channel.*explicitly approved/i);
  assert.match(troubleshooting, /Version mismatch or duplicate HUD/);
  assert.match(troubleshooting, /Neither command publishes, updates, or changes repository visibility/);
});

test("dependency inventory matches the zero-package private baseline", async () => {
  const packageManifest = JSON.parse(await readFile(path.join(root, "package.json"), "utf8"));
  const lockfile = JSON.parse(await readFile(path.join(root, "package-lock.json"), "utf8"));
  const inventory = await readFile(path.join(root, "docs/DEPENDENCIES.md"), "utf8");
  const notices = await readFile(path.join(root, "THIRD_PARTY_NOTICES.md"), "utf8");
  const swift = await readFile(path.join(root, "native/macos/PowerModeOverlay.swift"), "utf8");
  const browserHtml = await readFile(path.join(root, "overlay/index.html"), "utf8");

  for (const field of ["dependencies", "devDependencies", "optionalDependencies", "peerDependencies"]) {
    assert.deepEqual(packageManifest[field] ?? {}, {}, `${field} must be documented before use`);
  }
  assert.deepEqual(Object.keys(lockfile.packages ?? {}), [""]);
  assert.deepEqual(
    [...swift.matchAll(/^import\s+([A-Za-z0-9_]+)/gm)].map((match) => match[1]).sort(),
    ["AppKit", "ApplicationServices", "Foundation", "QuartzCore"]
  );
  assert.doesNotMatch(browserHtml, /(?:src|href)=["']https?:\/\//i);
  assert.match(inventory, /no third-party runtime or development packages/i);
  assert.match(inventory, /actions\/checkout@v5/);
  assert.match(inventory, /actions\/setup-node@v5/);
  assert.match(inventory, /project remains `UNLICENSED`/);
  assert.match(notices, /currently distributes no third-party/i);
});
