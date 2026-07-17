export const initialState = Object.freeze({
  phase: "observe",
  status: "ready",
  momentum: 0,
  bestMomentum: 0,
  confidence: 0,
  risk: 0,
  riskLevel: "low",
  currentActivity: "Waiting for Codex activity",
  steps: 0,
  edits: 0,
  addedLines: 0,
  removedLines: 0,
  verifications: 0,
  passedVerifications: 0,
  failedVerifications: 0,
  evidence: [],
  lastEditAt: null,
  lastVerificationAt: null,
  lastVerificationPassed: false,
  completion: null,
  sessionId: null
});

const clamp = (value, minimum = 0, maximum = 100) => Math.max(minimum, Math.min(maximum, value));

function riskLevel(value) {
  return value >= 65 ? "high" : value >= 30 ? "medium" : "low";
}

function activityLabel(event) {
  if (event.phase === "observe") return event.toolGroup === "search" ? "Searching the workspace" : "Reading context";
  if (event.phase === "verify") return `Running ${event.category || "verification"}`;
  if (event.phase === "act") return event.toolGroup === "command" ? "Executing a command" : "Preparing a change";
  return "Codex is working";
}

function verificationConfidence(category) {
  return category === "test" ? 38 : category === "build" ? 32 : category === "lint" ? 22 : 18;
}

function scopeRisk(event) {
  const changed = (event.addedLines || 0) + (event.removedLines || 0);
  return changed >= 150 ? 20 : changed >= 50 ? 12 : changed >= 15 ? 7 : 3;
}

export function reduceState(previous = initialState, event) {
  const state = { ...initialState, ...previous, sessionId: event.sessionId ?? previous.sessionId };
  state.evidence = Array.isArray(previous.evidence) ? [...previous.evidence] : [];

  if (event.type === "activity-start") {
    state.phase = event.phase || "observe";
    state.status = "working";
    state.currentActivity = activityLabel(event);
    state.steps += 1;
    state.momentum = clamp(state.momentum + (state.phase === "observe" ? 1 : 2));
    state.completion = null;
  } else if (event.type === "permission-request") {
    state.phase = "wait";
    state.status = "needs-attention";
    state.currentActivity = "Waiting for your approval";
  } else if (event.type === "edit") {
    state.phase = "act";
    state.status = "working";
    state.currentActivity = `Changed ${event.addedLines + event.removedLines} lines`;
    state.steps += 1;
    state.edits += 1;
    state.addedLines += event.addedLines;
    state.removedLines += event.removedLines;
    state.momentum = clamp(state.momentum + 7);
    state.confidence = clamp(state.confidence - 12);
    state.risk = clamp(state.risk + scopeRisk(event));
    state.lastEditAt = event.timestamp;
    state.lastVerificationPassed = false;
    state.completion = null;
  } else if (event.type === "verification") {
    state.verifications += 1;
    state.lastVerificationAt = event.timestamp;
    state.lastVerificationPassed = event.success;
    if (event.success) {
      state.phase = "verify";
      state.status = "verified";
      state.currentActivity = `${event.category} passed`;
      state.passedVerifications += 1;
      state.momentum = clamp(state.momentum + 10);
      state.confidence = clamp(state.confidence + verificationConfidence(event.category));
      state.risk = clamp(state.risk - 18);
      if (!state.evidence.includes(event.category)) state.evidence.push(event.category);
    } else {
      state.phase = "recover";
      state.status = "failed";
      state.currentActivity = `${event.category} failed — recovering`;
      state.failedVerifications += 1;
      state.momentum = clamp(state.momentum - 8);
      state.confidence = clamp(state.confidence - 28);
      state.risk = clamp(state.risk + 24);
    }
  } else if (event.type === "turn-stop") {
    const verifiedAfterEdit = state.lastVerificationPassed && state.lastVerificationAt &&
      (!state.lastEditAt || state.lastVerificationAt >= state.lastEditAt);
    state.phase = "complete";
    state.status = verifiedAfterEdit ? "verified" : state.edits ? "unverified" : "complete";
    state.completion = verifiedAfterEdit ? "verified" : state.edits ? "unverified" : "no-change";
    state.currentActivity = verifiedAfterEdit ? "Completed with evidence" : state.edits ? "Completed — verification recommended" : "Turn complete";
  }

  state.bestMomentum = Math.max(state.bestMomentum, state.momentum);
  state.riskLevel = riskLevel(state.risk);
  return state;
}
