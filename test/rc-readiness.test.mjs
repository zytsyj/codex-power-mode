import assert from "node:assert/strict";
import test from "node:test";
import { buildRcReadiness } from "../src/rc-readiness.mjs";

const version = "0.8.0+codex.current";
const passingReports = {
  security: { pluginVersion: version, passed: true },
  archive: { pluginVersion: version, passed: true },
  performance: { environment: { pluginVersion: version }, passed: true, method: { instruments: { status: "available" } } },
  stability: Object.assign({ pluginVersion: version }, Object.fromEntries([
    "serviceRestarted", "hudSurvivedRestart", "hudReconnected", "oneService", "oneHud", "settingsPreserved", "dataDirectoryConsistent"
  ].map((key) => [key, true]))),
  compatibility: { environment: { pluginVersion: version }, automated: { passed: true } }
};

test("RC readiness separates current automation from human and owner gates", () => {
  const report = buildRcReadiness({
    currentVersion: version,
    reports: passingReports,
    liveStatus: { service: { activity: { realEventsReceived: 2 } } },
    interactionSession: { status: "restored", pluginVersion: version, results: { cursor: "passed", injection: "passed" } }
  });
  assert.ok(report.automatic.every((gate) => gate.status === "passed"));
  assert.equal(report.realHook.status, "passed");
  assert.equal(report.interaction.status, "passed");
  assert.equal(report.instruments.status, "available-not-reviewed");
  assert.equal(report.status, "not-ready");
  assert.ok(report.blockers.includes("owner:license"));
  assert.ok(report.blockers.includes("instruments:available-not-reviewed"));
});

test("RC readiness marks old evidence stale and never upgrades synthetic evidence to a real Hook", () => {
  const reports = structuredClone(passingReports);
  reports.security.pluginVersion = "0.8.0+codex.old";
  reports.performance.method.instruments.status = "unavailable";
  const report = buildRcReadiness({
    currentVersion: version,
    reports,
    liveStatus: { service: { activity: { realEventsReceived: 0 } } },
    interactionSession: { status: "restored", pluginVersion: "0.8.0+codex.old", results: { cursor: "passed" } }
  });
  assert.equal(report.automatic.find((gate) => gate.name === "security").status, "stale");
  assert.equal(report.realHook.status, "pending");
  assert.equal(report.interaction.status, "stale");
  assert.equal(report.instruments.status, "unavailable");
  assert.equal(report.status, "not-ready");
});

test("RC readiness reports missing and failed evidence explicitly", () => {
  const report = buildRcReadiness({ currentVersion: version, reports: { archive: { pluginVersion: version, passed: false } } });
  assert.equal(report.automatic.find((gate) => gate.name === "archive").status, "failed");
  assert.equal(report.automatic.find((gate) => gate.name === "security").status, "missing");
  assert.equal(report.interaction.status, "missing");
});
