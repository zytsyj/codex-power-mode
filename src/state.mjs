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
  comboBrokenAt: null,
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
  turnStoppedAt: null,
  completion: null,
  sessionId: null,
  sessionSource: "unknown"
});

const clamp = (value, minimum = 0, maximum = 100) => Math.max(minimum, Math.min(maximum, value));
export const COMBO_DECAY_MS = 12_000;
export const COMBO_LOST_MS = 3_200;
export const FINAL_STATE_HOLD_MS = 3_000;
export const MOMENTUM_RETURN_MS = 4_000;
export const ABANDONED_ACTIVITY_MS = 5 * 60_000;

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
  state.comboBrokenAt = null;
}

function breakCombo(state, status = "broken", timestamp = null) {
  if (state.combo > 0) state.comboBreaks += 1;
  state.combo = 0;
  state.comboStatus = status;
  state.comboHoldUntil = null;
  state.comboExpiresAt = null;
  state.comboBrokenAt = status === "broken" ? timestamp : null;
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

export function comboDisplayStatus(state, now = Date.now()) {
  const current = typeof now === "number" ? now : Date.parse(now);
  if (comboProgress(state, current) > 0) return state.comboStatus ?? "decaying";
  const explicitBreak = Date.parse(state.comboBrokenAt);
  const naturalBreak = Date.parse(state.comboExpiresAt);
  const disconnectedAt = Number.isFinite(explicitBreak) ? explicitBreak : naturalBreak;
  return Number.isFinite(current) && Number.isFinite(disconnectedAt) && current < disconnectedAt + COMBO_LOST_MS ? "broken" : "idle";
}

export function presentationSnapshot(state, now = Date.now()) {
  const current = typeof now === "number" ? now : Date.parse(now);
  const explicitStopAt = Date.parse(state.turnStoppedAt);
  const lastActivityAt = Date.parse(state.lastActivityAt);
  const canSettleAbandoned = ["observe", "act", "verify"].includes(state.phase) &&
    state.status !== "needs-attention" && state.status !== "failed";
  const stoppedAt = Number.isFinite(explicitStopAt)
    ? explicitStopAt
    : canSettleAbandoned && Number.isFinite(lastActivityAt)
      ? lastActivityAt + ABANDONED_ACTIVITY_MS
      : Number.NaN;
  const momentum = clamp(state.momentum ?? 0);
  if (!Number.isFinite(current) || !Number.isFinite(stoppedAt)) {
    return { ...state, momentum, idle: false, settled: false, returning: false };
  }
  const explicitBreak = Date.parse(state.comboBrokenAt);
  const naturalBreak = Date.parse(state.comboExpiresAt);
  const disconnectedAt = Number.isFinite(explicitBreak) ? explicitBreak : naturalBreak;
  const comboSettledAt = Number.isFinite(disconnectedAt) ? disconnectedAt + COMBO_LOST_MS : 0;
  const idleAt = Math.max(stoppedAt + FINAL_STATE_HOLD_MS, comboSettledAt);
  if (current < idleAt) return { ...state, momentum, idle: false, settled: false, returning: true };

  const progress = clamp((current - idleAt) / MOMENTUM_RETURN_MS, 0, 1);
  return {
    ...state,
    phase: "idle",
    status: "ready",
    completion: null,
    currentActivity: "Waiting for Codex activity",
    momentum: Math.round(momentum * (1 - progress)),
    idle: true,
    settled: progress >= 1,
    returning: progress < 1
  };
}

function riskLevel(value) {
  return value >= 65 ? "high" : value >= 30 ? "medium" : "low";
}

function activityLabel(event) {
  if (event.phase === "observe") {
    if (event.toolGroup === "prompt") return "Understanding request";
    return event.toolGroup === "search" ? "Searching the workspace" : "Reading context";
  }
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
  const startsNewTurn = !sessionChanged && prior.phase === "complete" && event.type !== "turn-stop";
  const turnBase = startsNewTurn ? {
    ...initialState,
    bestMomentum: prior.bestMomentum ?? 0,
    bestCombo: prior.bestCombo ?? 0,
    sessionId: prior.sessionId ?? null,
    sessionSource: prior.sessionSource ?? "unknown"
  } : prior;
  const state = {
    ...initialState,
    ...turnBase,
    sessionId: event.sessionId ?? turnBase.sessionId,
    sessionSource: event.sessionSource && event.sessionSource !== "unknown" ? event.sessionSource : turnBase.sessionSource
  };
  state.evidence = Array.isArray(turnBase.evidence) ? [...turnBase.evidence] : [];
  if (event.type !== "turn-stop") state.turnStoppedAt = null;

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
    breakCombo(state, "broken", event.timestamp);
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
      breakCombo(state, "broken", event.timestamp);
    }
  } else if (event.type === "turn-stop") {
    const stoppedWhileWaiting = state.phase === "wait";
    const verifiedAfterEdit = state.lastVerificationPassed && state.lastVerificationAt &&
      (!state.lastEditAt || state.lastVerificationAt >= state.lastEditAt);
    state.phase = "complete";
    state.turnStoppedAt = event.timestamp;
    state.status = verifiedAfterEdit ? "verified" : stoppedWhileWaiting ? "cancelled" : state.edits ? "unverified" : "complete";
    state.completion = verifiedAfterEdit ? "verified" : stoppedWhileWaiting ? "cancelled" : state.edits ? "unverified" : "no-change";
    state.currentActivity = verifiedAfterEdit ? "Completed with evidence" : stoppedWhileWaiting ? "Approval was not granted" : state.edits ? "Completed — verification recommended" : "Turn complete";
    if (verifiedAfterEdit && state.combo > 0) {
      state.comboStatus = "complete";
      state.comboHoldUntil = timestampAfter(event.timestamp, 3_200);
      state.comboExpiresAt = timestampAfter(event.timestamp, 3_200 + COMBO_DECAY_MS);
    } else {
      const comboStatus = stoppedWhileWaiting || state.edits ? "broken" : "idle";
      breakCombo(state, comboStatus, event.timestamp);
    }
  }

  state.bestMomentum = Math.max(state.bestMomentum, state.momentum);
  state.bestCombo = Math.max(state.bestCombo, state.combo);
  state.riskLevel = riskLevel(state.risk);
  return state;
}
