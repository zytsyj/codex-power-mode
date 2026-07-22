import assert from "node:assert/strict";
import test from "node:test";
import { powerModeDoctor, renderDoctorReport } from "../src/doctor.mjs";

const healthyStatus = {
  service: { running: true, ok: true, serviceVersion: "1.0.0", dataDir: "/tmp/power-mode" },
  nativeOverlay: { running: true },
  connection: { hudConnected: true, hookActivity: "idle" }
};

test("doctor reports a healthy single-instance installation", () => {
  const report = powerModeDoctor({
    status: healthyStatus,
    identity: { version: "1.0.0" },
    expectedDataDir: "/tmp/power-mode",
    platform: "darwin",
    serverProcessCount: 1,
    nativeProcessCount: 1
  });
  assert.equal(report.overall, "ok");
  assert.match(renderDoctorReport(report), /Power Mode is healthy/);
});

test("doctor exposes stale versions, duplicate processes, and unverified hooks", () => {
  const report = powerModeDoctor({
    status: { ...healthyStatus, service: { ...healthyStatus.service, serviceVersion: "0.9.0" }, connection: { hudConnected: false, hookActivity: "waiting-for-task" } },
    identity: { version: "1.0.0" },
    expectedDataDir: "/tmp/power-mode",
    platform: "darwin",
    serverProcessCount: 2,
    nativeProcessCount: 0
  });
  assert.equal(report.overall, "fail");
  assert.equal(report.checks.find((check) => check.id === "hooks").level, "warn");
  assert.match(renderDoctorReport(report), /Power Mode needs attention/);
});
