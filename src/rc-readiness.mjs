const automaticGateNames = Object.freeze(["security", "archive", "performance", "stability", "compatibility"]);

function reportVersion(report) {
  return report?.pluginVersion ?? report?.environment?.pluginVersion ?? null;
}

function reportPassed(name, report) {
  if (!report) return false;
  if (name === "stability") {
    return ["serviceRestarted", "hudSurvivedRestart", "hudReconnected", "oneService", "oneHud", "settingsPreserved", "dataDirectoryConsistent"]
      .every((key) => report[key] === true);
  }
  if (name === "compatibility") return report.automated?.passed === true;
  return report.passed === true;
}

function automaticGate(name, report, currentVersion) {
  if (!report) return { name, status: "missing", versionCurrent: false };
  const version = reportVersion(report);
  const versionCurrent = version === currentVersion;
  return {
    name,
    status: reportPassed(name, report) ? (versionCurrent ? "passed" : "stale") : "failed",
    versionCurrent
  };
}

function interactionGate(session, currentVersion) {
  const results = Object.values(session?.results ?? {});
  const counts = { passed: 0, failed: 0, pending: 0, unavailable: 0 };
  for (const result of results) {
    if (Object.hasOwn(counts, result)) counts[result] += 1;
  }
  const versionCurrent = session?.pluginVersion === currentVersion;
  let status = "missing";
  if (session) {
    if (counts.failed > 0) status = "failed";
    else if (results.length > 0 && counts.passed === results.length && session.status === "restored") status = versionCurrent ? "passed" : "stale";
    else if (counts.passed > 0 && !versionCurrent) status = "stale";
    else status = "pending";
  }
  return { status, versionCurrent, sessionRestored: session?.status === "restored", counts };
}

export function buildRcReadiness({ currentVersion, reports = {}, liveStatus = null, interactionSession = null }) {
  const automatic = automaticGateNames.map((name) => automaticGate(name, reports[name], currentVersion));
  const realEventsReceived = Number(liveStatus?.service?.activity?.realEventsReceived) || 0;
  const realHook = {
    status: realEventsReceived > 0 ? "passed" : "pending",
    observed: realEventsReceived > 0
  };
  const interaction = interactionGate(interactionSession, currentVersion);
  const instrumentsStatus = reports.performance?.method?.instruments?.status ?? "missing";
  const instruments = {
    status: instrumentsStatus === "available" ? "available-not-reviewed" : instrumentsStatus,
    accepted: false
  };
  const ownerDecisions = ["license", "security-channel", "support-range", "ci-action-pinning", "repository-publication", "release-version"]
    .map((name) => ({ name, status: "pending-owner-decision" }));
  const blockers = [
    ...automatic.filter((gate) => gate.status !== "passed").map((gate) => `automatic:${gate.name}:${gate.status}`),
    ...(realHook.status === "passed" ? [] : ["real-hook:pending"]),
    ...(interaction.status === "passed" ? [] : [`interaction:${interaction.status}`]),
    ...(instruments.accepted ? [] : [`instruments:${instruments.status}`]),
    ...ownerDecisions.map((decision) => `owner:${decision.name}`)
  ];
  return {
    schemaVersion: 1,
    currentVersion,
    status: blockers.length === 0 ? "candidate-ready" : "not-ready",
    automatic,
    realHook,
    interaction,
    instruments,
    ownerDecisions,
    blockers,
    privacy: "Only gate names, aggregate counts, version equality, and pass/pending/stale status are reported"
  };
}
