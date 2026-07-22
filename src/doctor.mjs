import path from "node:path";

export function powerModeDoctor({ status, identity, expectedDataDir, platform = process.platform, serverProcessCount = 0, nativeProcessCount = 0, accessibility = null }) {
  const checks = [];
  const add = (id, level, message) => checks.push({ id, level, message });
  const service = status?.service ?? {};
  const overlay = status?.nativeOverlay ?? {};

  add("service", service.running && service.ok ? "ok" : "fail", service.running && service.ok ? "Local service is responding" : "Local service is not responding");
  if (service.running) {
    add(
      "version",
      service.serviceVersion === identity.version ? "ok" : "fail",
      service.serviceVersion === identity.version ? `Running version ${identity.version}` : `Running version ${service.serviceVersion ?? "unknown"}; expected ${identity.version}`
    );
    add(
      "data-directory",
      service.dataDir && path.resolve(service.dataDir) === path.resolve(expectedDataDir) ? "ok" : "fail",
      service.dataDir && path.resolve(service.dataDir) === path.resolve(expectedDataDir) ? "Runtime data directory is consistent" : "Runtime data directory does not match this installation"
    );
  }
  add("service-instance", serverProcessCount === 1 ? "ok" : "fail", serverProcessCount === 1 ? "One service instance is running" : `${serverProcessCount} service instances are running`);

  if (platform === "darwin") {
    add("native-overlay", overlay.running ? "ok" : "fail", overlay.running ? "Native HUD is running" : "Native HUD is not running");
    add("native-instance", nativeProcessCount === 1 ? "ok" : "fail", nativeProcessCount === 1 ? "One HUD instance is running" : `${nativeProcessCount} HUD instances are running`);
    if (overlay.running) {
      add("hud-connection", status?.connection?.hudConnected ? "ok" : "warn", status?.connection?.hudConnected ? "HUD is connected to the event stream" : "HUD is running but not connected yet");
    }
    if (overlay.configuration?.typingCombo === true) {
      add(
        "accessibility",
        accessibility?.accessibilityTrusted === true ? "ok" : "warn",
        accessibility?.accessibilityTrusted === true ? "macOS Accessibility permission is granted" : "Typing Combo is on but macOS Accessibility permission is not granted"
      );
      if (accessibility?.accessibilityTrusted === true && accessibility?.frontmostBundle === "com.openai.codex") {
        add(
          "caret",
          accessibility?.caretElementFound === true ? "ok" : "warn",
          accessibility?.caretElementFound === true ? "Codex input cursor is available for effects" : "Click the Codex input box to make cursor effects available"
        );
      }
    } else {
      add("accessibility", "ok", "Typing Combo is off; Accessibility permission is not required");
    }
  }

  add(
    "hooks",
    status?.connection?.hookActivity === "receiving" || status?.connection?.hookActivity === "idle" ? "ok" : "warn",
    status?.connection?.hookActivity === "receiving" || status?.connection?.hookActivity === "idle"
      ? "Codex desktop lifecycle events have been received"
      : "Waiting for the next trusted Codex desktop task to verify hooks"
  );

  const overall = checks.some((check) => check.level === "fail") ? "fail" : checks.some((check) => check.level === "warn") ? "warn" : "ok";
  return { overall, checks };
}

export function renderDoctorReport(report) {
  const title = report.overall === "ok" ? "Power Mode is healthy" : report.overall === "warn" ? "Power Mode is running with notices" : "Power Mode needs attention";
  const symbols = { ok: "✓", warn: "!", fail: "×" };
  return `${title}\n${report.checks.map((check) => `${symbols[check.level]} ${check.message}`).join("\n")}\n`;
}
