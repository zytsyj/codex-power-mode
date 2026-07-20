export const initialState = Object.freeze({
  phase: "observe",
  status: "ready",
  momentum: 0,
  bestMomentum: 0,
  combo: 0,
  bestCombo: 0,
  comboBreaks: 0,
  comboStatus: "idle",
  comboLastAt: null,
  comboHoldUntil: null,
  comboExpiresAt: null,
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
  lastActivityAt: null,
  lastActivitySignature: null,
  lastEditAt: null,
  lastVerificationAt: null,
  lastVerificationPassed: false,
  completion: null,
  sessionId: null
});

const clamp = (value, minimum = 0, maximum = 100) => Math.max(minimum, Math.min(maximum, value));
export const COMBO_DECAY_MS = 12_000;

const COMBO_HOLD_MS = Object.freeze({ observe: 0, act: 15_000, verify: 90_000 });

function timestampAfter(timestamp, offsetMs) {
  const value = Date.parse(timestamp);
  return new Date((Number.isFinite(value) ? value : 0) + offsetMs).toISOString();
}

function advanceCombo(state, event, weight = 1, holdMs = 0, forceNew = false) {
  const eventAt = Date.parse(event.timestamp);
  const expiresAt = Date.parse(state.comboExpiresAt);
  const continues = !forceNew && state.combo > 0 && Number.isFinite(eventAt) &&
    Number.isFinite(expiresAt) && eventAt <= expiresAt;
  if (!continues && state.combo > 0) state.comboBreaks += 1;
  state.combo = (continues ? state.combo : 0) + weight;
  state.comboStatus = holdMs > 0 ? "holding" : "decaying";
  state.comboLastAt = event.timestamp;
  state.comboHoldUntil = timestampAfter(event.timestamp, holdMs);
  state.comboExpiresAt = timestampAfter(event.timestamp, holdMs + COMBO_DECAY_MS);
}

function breakCombo(state, status = "broken") {
  if (state.combo > 0) state.comboBreaks += 1;
  state.combo = 0;
  state.comboStatus = status;
  state.comboHoldUntil = null;
  state.comboExpiresAt = null;
}

export function comboProgress(state, now = Date.now()) {
  if (!state.combo || !state.comboExpiresAt) return 0;
  const current = typeof now === "number" ? now : Date.parse(now);
  const holdUntil = Date.parse(state.comboHoldUntil || state.comboLastAt);
  const expiresAt = Date.parse(state.comboExpiresAt);
  if (![current, holdUntil, expiresAt].every(Number.isFinite)) return 0;
  if (current <= holdUntil) return 1;
  if (current >= expiresAt) return 0;
  return clamp((expiresAt - current) / Math.max(1, expiresAt - holdUntil), 0, 1);
}

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

function activitySignature(event) {
  return `${event.phase || "observe"}:${event.toolGroup || "tool"}:${event.category || ""}`;
}

export function shouldCoalesceActivity(previous, event, windowMs = 900) {
  if (event.type !== "activity-start" || event.phase !== "observe" || windowMs <= 0) return false;
  if (!previous.lastActivityAt || previous.lastActivitySignature !== activitySignature(event)) return false;
  const elapsed = Date.parse(event.timestamp) - Date.parse(previous.lastActivityAt);
  return Number.isFinite(elapsed) && elapsed >= 0 && elapsed < windowMs;
}

export function reduceState(previous = initialState, event) {
  const sessionChanged = Boolean(previous.sessionId && event.sessionId && previous.sessionId !== event.sessionId);
  const prior = sessionChanged ? initialState : previous;
  const state = { ...initialState, ...prior, sessionId: event.sessionId ?? prior.sessionId };
  state.evidence = Array.isArray(prior.evidence) ? [...prior.evidence] : [];
  const startsNewTurn = state.phase === "complete";

  if (event.type === "activity-start") {
    state.phase = event.phase || "observe";
    state.status = "working";
    state.currentActivity = activityLabel(event);
    state.steps += 1;
    state.momentum = clamp(state.momentum + (state.phase === "observe" ? 1 : 2));
    state.completion = null;
    state.lastActivityAt = event.timestamp;
    state.lastActivitySignature = activitySignature(event);
    advanceCombo(state, event, 1, COMBO_HOLD_MS[state.phase] ?? 0, startsNewTurn);
  } else if (event.type === "permission-request") {
    state.phase = "wait";
    state.status = "needs-attention";
    state.currentActivity = "Waiting for your approval";
    if (state.combo > 0) {
      state.comboStatus = "waiting";
      state.comboHoldUntil = timestampAfter(event.timestamp, 15_000);
      state.comboExpiresAt = timestampAfter(event.timestamp, 15_000 + COMBO_DECAY_MS);
    }
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
    advanceCombo(state, event, 1, 0, startsNewTurn);
  } else if (event.type === "edit-failure") {
    state.phase = "recover";
    state.status = "failed";
    state.currentActivity = "Repairing a failed edit";
    state.completion = null;
    breakCombo(state);
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
      advanceCombo(state, event, 2, 0, startsNewTurn);
    } else {
      state.phase = "recover";
      state.status = "failed";
      state.currentActivity = `${event.category} failed — recovering`;
      state.failedVerifications += 1;
      state.momentum = clamp(state.momentum - 8);
      state.confidence = clamp(state.confidence - 28);
      state.risk = clamp(state.risk + 24);
      breakCombo(state);
    }
  } else if (event.type === "turn-stop") {
    const verifiedAfterEdit = state.lastVerificationPassed && state.lastVerificationAt &&
      (!state.lastEditAt || state.lastVerificationAt >= state.lastEditAt);
    state.phase = "complete";
    state.status = verifiedAfterEdit ? "verified" : state.edits ? "unverified" : "complete";
    state.completion = verifiedAfterEdit ? "verified" : state.edits ? "unverified" : "no-change";
    state.currentActivity = verifiedAfterEdit ? "Completed with evidence" : state.edits ? "Completed — verification recommended" : "Turn complete";
    if (verifiedAfterEdit && state.combo > 0) {
      state.comboStatus = "complete";
      state.comboHoldUntil = timestampAfter(event.timestamp, 3_200);
      state.comboExpiresAt = timestampAfter(event.timestamp, 3_200 + COMBO_DECAY_MS);
    } else {
      breakCombo(state, state.edits ? "broken" : "idle");
    }
  }

  state.bestMomentum = Math.max(state.bestMomentum, state.momentum);
  state.bestCombo = Math.max(state.bestCombo, state.combo);
  state.riskLevel = riskLevel(state.risk);
  return state;
}
