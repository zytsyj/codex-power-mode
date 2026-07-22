import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import path from "node:path";
import process from "node:process";

const root = path.resolve(import.meta.dirname, "..");
const tracked = execFileSync("git", ["ls-files", "-z"], { cwd: root })
  .toString("utf8")
  .split("\0")
  .filter(Boolean);

const forbiddenTrackedNames = [
  /(^|\/)\.power-mode\//,
  /(^|\/)overlay-config\.json$/,
  /(^|\/)state\.json$/,
  /(^|\/)service-token$/,
  /(^|\/)codex-power-mode-overlay$/,
  /\.log$/
];

const textChecks = [
  {
    label: "developer-specific macOS home path",
    pattern: /\/Users\/(?!example\/|me\/|tester\/)[A-Za-z0-9._-]+\//
  },
  {
    label: "developer-specific Linux home path",
    pattern: /\/home\/(?!example\/|runner\/|tester\/)[A-Za-z0-9._-]+\//
  },
  {
    label: "private key material",
    pattern: /-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/
  }
];

const violations = [];
for (const filename of tracked) {
  if (forbiddenTrackedNames.some((pattern) => pattern.test(filename))) {
    violations.push(`${filename}: generated runtime artifact`);
    continue;
  }
  let source;
  try {
    source = readFileSync(path.join(root, filename), "utf8");
  } catch {
    continue;
  }
  for (const check of textChecks) {
    if (check.pattern.test(source)) violations.push(`${filename}: ${check.label}`);
  }
}

if (violations.length > 0) {
  console.error("Release hygiene validation failed:");
  for (const violation of violations) console.error(`- ${violation}`);
  process.exitCode = 1;
} else {
  console.log("Release hygiene validation passed");
}
