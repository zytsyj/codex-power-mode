#!/usr/bin/env node
import { access, readFile } from "node:fs/promises";

const manifestUrl = new URL("../.codex-plugin/plugin.json", import.meta.url);
const hooksUrl = new URL("../hooks/hooks.json", import.meta.url);
const marketplaceUrl = new URL("../.agents/plugins/marketplace.json", import.meta.url);
const manifest = JSON.parse(await readFile(manifestUrl, "utf8"));
const hooks = JSON.parse(await readFile(hooksUrl, "utf8"));
const marketplace = JSON.parse(await readFile(marketplaceUrl, "utf8"));

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
if (manifest.license !== "MIT") throw new Error("Public plugin manifest must use the MIT license");
if (manifest.repository !== "https://github.com/zytsyj/codex-power-mode") throw new Error("Public repository metadata is missing");
const marketplaceEntry = marketplace.plugins?.find((entry) => entry.name === manifest.name);
if (!marketplaceEntry) throw new Error("Public marketplace entry is missing");
if (marketplaceEntry.source?.source !== "url" ||
    marketplaceEntry.source?.url !== "https://github.com/zytsyj/codex-power-mode.git") {
  throw new Error("Public marketplace must install the repository-root plugin from GitHub");
}
if (!["AVAILABLE", "INSTALLED_BY_DEFAULT", "NOT_AVAILABLE"].includes(marketplaceEntry.policy?.installation)) {
  throw new Error("Marketplace installation policy is invalid");
}
if (!["ON_INSTALL", "ON_USE"].includes(marketplaceEntry.policy?.authentication)) {
  throw new Error("Marketplace authentication policy is invalid");
}
await access(new URL(`../${manifest.skills.replace(/^\.\//, "")}`, import.meta.url));
process.stdout.write("Manifest validation passed\n");
