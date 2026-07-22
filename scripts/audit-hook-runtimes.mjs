#!/usr/bin/env node
import { auditHookRuntimes } from "../src/hook-runtime.mjs";
import { powerModeDataDir } from "../src/paths.mjs";

const report = await auditHookRuntimes(powerModeDataDir());
if (process.argv.includes("--json")) {
  process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
} else {
  const mebibytes = (report.totalBytes / 1024 / 1024).toFixed(2);
  process.stdout.write([
    "Power Mode Hook runtime audit (read-only)",
    `Current: ${report.currentVersion ?? "not linked"}`,
    `Stored: ${report.runtimeCount} versions, ${mebibytes} MiB`,
    `Policy candidate: keep ${report.retention} newest plus the linked current version`,
    `Would keep: ${report.keepCount}`,
    `Would become eligible: ${report.eligibleCount}`,
    "No files were removed."
  ].join("\n") + "\n");
}
