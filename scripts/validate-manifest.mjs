#!/usr/bin/env node
import { access, readFile } from "node:fs/promises";

const manifestUrl = new URL("../.codex-plugin/plugin.json", import.meta.url);
const hooksUrl = new URL("../hooks/hooks.json", import.meta.url);
const manifest = JSON.parse(await readFile(manifestUrl, "utf8"));
const hooks = JSON.parse(await readFile(hooksUrl, "utf8"));

const requiredStrings = [
  ["name", manifest.name],
  ["version", manifest.version],
  ["description", manifest.description],
  ["author.name", manifest.author?.name],
  ["interface.displayName", manifest.interface?.displayName],
  ["interface.shortDescription", manifest.interface?.shortDescription],
  ["interface.longDescription", manifest.interface?.longDescription],
  ["interface.developerName", manifest.interface?.developerName],
  ["interface.category", manifest.interface?.category]
];

for (const [field, value] of requiredStrings) {
  if (typeof value !== "string" || !value.trim()) throw new Error(`Missing required manifest field: ${field}`);
}
if (!/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(manifest.name)) throw new Error("Plugin name must be kebab-case");
if (!/^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$/.test(manifest.version)) throw new Error("Plugin version must be semver");
if (!Array.isArray(manifest.interface.defaultPrompt) || manifest.interface.defaultPrompt.length > 3) {
  throw new Error("interface.defaultPrompt must be an array with at most three entries");
}
if (!hooks.hooks?.PostToolUse || !hooks.hooks?.Stop) throw new Error("Required lifecycle hooks are missing");
await access(new URL(`../${manifest.skills.replace(/^\.\//, "")}`, import.meta.url));
process.stdout.write("Manifest validation passed\n");
