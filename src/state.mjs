export const initialState = Object.freeze({
  phase: "observe",
  status: "ready",
  momentum: 0,
  bestMomentum: 0,
  energyUpdatedAt: null,
  combo: 0,
  bestCombo: 0,
  comboBreaks: 0,
  comboStatus: "idle",
  comboLastAt: null,
  comboHoldUntil: null,
  comboExpiresAt: null,
  comboBrokenAt: null,
  comboRelinkedAt: null,
  verificationReward: null,
  verificationRewardAt: null,
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
  lastFailureAt: null,
  turnStoppedAt: null,
  completion: null,
  mixedLastCompletion: null,
  mixedLastCompletionAt: null,
  sessionId: null,
  sessionSource: "unknown"
});

export const ENERGY_MAX = 999;
export const ENERGY_GAIN_MULTIPLIER = 0.72;
export const ENERGY_GAIN_PRESETS = Object.freeze([0.3, 0.4, 0.5, 0.6, 0.72, 0.85, 1, 1.15, 1.3, 1.5]);
export const ENERGY_STAGES = Object.freeze([
  Object.freeze({ name: "idle", lower: 0, upper: 0 }),
  Object.freeze({ name: "awakening", lower: 1, upper: 199 }),
  Object.freeze({ name: "charging", lower: 200, upper: 449 }),
  Object.freeze({ name: "driving", lower: 450, upper: 699 }),
  Object.freeze({ name: "critical", lower: 700, upper: 899 }),
  Object.freeze({ name: "peak", lower: 900, upper: 999 })
]);
const clamp = (value, minimum = 0, maximum = 100) => Math.max(minimum, Math.min(maximum, value));
const clampEnergy = (value) => clamp(value, 0, ENERGY_MAX);
export const COMBO_DECAY_MS = 14_000;
export const COMBO_LOST_MS = 3_200;
export const COMBO_RELINK_FEEDBACK_MS = 1_600;
export const VERIFICATION_REWARD_HOLD_MS = 1_800;
export const FINAL_STATE_HOLD_MS = 3_000;
export const MOMENTUM_RETURN_MS = 45_000;
export const ENERGY_IDLE_GRACE_MS = 20_000;
export const ENERGY_DECAY_MS = 90_000;
export const ABANDONED_ACTIVITY_MS = 5 * 60_000;
export const RECOVERY_TIMEOUT_MS = 15_000;

const COMBO_HOLD_MS = Object.freeze({ observe: 0, act: 15_000, verify: 90_000 });
export function normalizeEnergyGainMultiplier(value) {
  const parsed = Number(value);
  const preset = ENERGY_GAIN_PRESETS.find((candidate) => Math.abs(candidate - parsed) < 0.001);
  if (preset !== undefined) return preset;
  if (Math.abs(parsed - 0.55) < 0.001) return 0.5;
  if (Math.abs(parsed - 0.9) < 0.001) return 0.85;
  if (Math.abs(parsed - 1.1) < 0.001) return 1.15;
  return ENERGY_GAIN_MULTIPLIER;
}

const scaledEnergyGain = (value, multiplier = ENERGY_GAIN_MULTIPLIER) =>
  Math.round(value * normalizeEnergyGainMultiplier(multiplier));

function timestampAfter(timestamp, offsetMs) {
  const value = Date.parse(timestamp);
  return new Date((Number.isFinite(value) ? value : 0) + offsetMs).toISOString();
}

function advanceCombo(state, event, weight = 1, holdMs = 0, forceNew = false, status = null) {
  const eventAt = Date.parse(event.timestamp);
  const expiresAt = Date.parse(state.comboExpiresAt);
  const continues = !forceNew && state.combo > 0 && Number.isFinite(eventAt) &&
    Number.isFinite(expiresAt) && eventAt <= expiresAt;
  const hadCombo = state.combo > 0;
  const relinked = !forceNew && hadCombo && !continues;
  if (!continues && hadCombo) state.comboBreaks += 1;
  state.combo = (continues ? state.combo : 0) + weight;
  state.comboStatus = status ?? (holdMs > 0 ? "holding" : "decaying");
  state.comboLastAt = event.timestamp;
  state.comboHoldUntil = timestampAfter(event.timestamp, holdMs);
  state.comboExpiresAt = timestampAfter(event.timestamp, holdMs + COMBO_DECAY_MS);
  state.comboBrokenAt = null;
  state.comboRelinkedAt = relinked ? event.timestamp : continues ? state.comboRelinkedAt : null;
}

function breakCombo(state, status = "broken", timestamp = null) {
  if (state.combo > 0) state.comboBreaks += 1;
  state.combo = 0;
  state.comboStatus = status;
  state.comboHoldUntil = null;
  state.comboExpiresAt = null;
  state.comboBrokenAt = status === "broken" ? timestamp : null;
  state.comboRelinkedAt = null;
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

export function energyLevel(momentum = 0) {
  return energyStage(momentum).name;
}

export function energyStage(momentum = 0) {
  const value = clampEnergy(momentum);
  const stage = ENERGY_STAGES.findLast((candidate) => value >= candidate.lower) ?? ENERGY_STAGES[0];
  if (stage.upper <= stage.lower) return { ...stage, value, progress: value >= stage.upper ? 1 : 0 };
  return {
    ...stage,
    value,
    progress: clamp((value - stage.lower) / (stage.upper - stage.lower), 0, 1)
  };
}

export function typingChargeForCombo(combo = 0, multiplier = ENERGY_GAIN_MULTIPLIER) {
  const count = Math.max(0, Math.min(200, Number.isFinite(combo) ? Math.floor(combo) : 0));
  if (count >= 40) return scaledEnergyGain(90, multiplier);
  if (count >= 20) return scaledEnergyGain(55, multiplier);
  if (count >= 10) return scaledEnergyGain(32, multiplier);
  if (count >= 5) return scaledEnergyGain(16, multiplier);
  return count > 0 ? scaledEnergyGain(6, multiplier) : 0;
}

export function comboStage(state, now = Date.now()) {
  const progress = comboProgress(state, now);
  const status = comboDisplayStatus(state, now);
  if (status === "broken") return "lost";
  if (status === "idle") return "idle";
  if (state.comboStatus === "reward" || state.comboStatus === "complete") {
    if (state.verificationReward === "record") return "record";
    if (state.verificationReward === "confirmation") return "confirmed";
    return "reward";
  }
  const current = typeof now === "number" ? now : Date.parse(now);
  const relinkedAt = Date.parse(state.comboRelinkedAt);
  if (Number.isFinite(current) && Number.isFinite(relinkedAt) && current < relinkedAt + COMBO_RELINK_FEEDBACK_MS) return "relinked";
  if (progress <= 0.25) return "critical";
  if ((state.combo ?? 0) < 5) return "ignition";
  if ((state.combo ?? 0) < 10) return "linked";
  if ((state.combo ?? 0) < 20) return "accelerated";
  if ((state.combo ?? 0) < 40) return "heated";
  return "extreme";
}

export function energyAt(state, now = Date.now()) {
  const current = typeof now === "number" ? now : Date.parse(now);
  const energy = clampEnergy(state?.momentum ?? 0);
  if (!energy || !Number.isFinite(current)) return energy;
  if (state?.status === "needs-attention" || state?.phase === "wait") return energy;
  const updatedAt = Date.parse(state?.energyUpdatedAt ?? state?.lastActivityAt ?? "");
  if (!Number.isFinite(updatedAt)) return energy;
  const decayStartsAt = updatedAt + ENERGY_IDLE_GRACE_MS;
  if (current <= decayStartsAt) return energy;
  const progress = clamp((current - decayStartsAt) / ENERGY_DECAY_MS, 0, 1);
  return Math.round(energy * (1 - progress));
}

export function presentationSnapshot(state, now = Date.now()) {
  const current = typeof now === "number" ? now : Date.parse(now);
  const explicitStopAt = Date.parse(state.turnStoppedAt);
  const lastActivityAt = Date.parse(state.lastActivityAt);
  const lastFailureAt = Date.parse(state.lastFailureAt ?? state.lastVerificationAt ?? state.lastActivityAt);
  const canSettleAbandoned = ["observe", "act", "verify"].includes(state.phase) &&
    state.status !== "needs-attention" && state.status !== "failed";
  const canSettleRecovery = state.phase === "recover" && state.status === "failed" && Number.isFinite(lastFailureAt);
  const stoppedAt = Number.isFinite(explicitStopAt)
    ? explicitStopAt
    : canSettleRecovery
      ? lastFailureAt + RECOVERY_TIMEOUT_MS
      : canSettleAbandoned && Number.isFinite(lastActivityAt)
      ? lastActivityAt + ABANDONED_ACTIVITY_MS
      : Number.NaN;
  const momentum = energyAt(state, current);
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
  const returnedMomentum = Math.round(momentum * (1 - progress));
  const settled = returnedMomentum <= 0 || progress >= 1;
  return {
    ...state,
    phase: "idle",
    status: "ready",
    completion: null,
    currentActivity: "Waiting for Codex activity",
    momentum: returnedMomentum,
    combo: 0,
    comboStatus: "idle",
    comboHoldUntil: null,
    comboExpiresAt: null,
    comboBrokenAt: null,
    comboRelinkedAt: null,
    verificationReward: null,
    verificationRewardAt: null,
    idle: true,
    settled,
    returning: !settled
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

export function reduceState(previous = initialState, event, { energyGainMultiplier = ENERGY_GAIN_MULTIPLIER } = {}) {
  const gainMultiplier = normalizeEnergyGainMultiplier(energyGainMultiplier);
  const sessionChanged = Boolean(previous.sessionId && event.sessionId && previous.sessionId !== event.sessionId);
  const prior = sessionChanged ? initialState : previous;
  const startsNewTurn = !sessionChanged && prior.phase === "complete" && event.type !== "turn-stop";
  const eventAt = Date.parse(event.timestamp);
  const carriedEnergy = energyAt(prior, eventAt);
  const turnBase = startsNewTurn ? {
    ...initialState,
    momentum: carriedEnergy,
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
  state.momentum = carriedEnergy;
  state.evidence = Array.isArray(turnBase.evidence) ? [...turnBase.evidence] : [];
  if (event.type !== "turn-stop") {
    state.turnStoppedAt = null;
    state.mixedLastCompletion = null;
    state.mixedLastCompletionAt = null;
  }

  if (event.type === "activity-start") {
    state.phase = event.phase || "observe";
    state.status = "working";
    state.currentActivity = activityLabel(event);
    state.steps += 1;
    const gain = scaledEnergyGain(state.phase === "observe" ? 14 : state.phase === "verify" ? 20 : 28, gainMultiplier);
    state.momentum = clampEnergy(state.momentum + gain);
    state.completion = null;
    state.lastActivityAt = event.timestamp;
    state.energyUpdatedAt = event.timestamp;
    state.lastActivitySignature = activitySignature(event);
    advanceCombo(state, event, 1, COMBO_HOLD_MS[state.phase] ?? 0, startsNewTurn);
  } else if (event.type === "input-charge") {
    state.phase = "observe";
    state.status = "working";
    state.currentActivity = "Understanding request";
    state.momentum = clampEnergy(state.momentum + typingChargeForCombo(event.inputCombo, gainMultiplier));
    state.lastActivityAt = event.timestamp;
    state.energyUpdatedAt = event.timestamp;
    state.completion = null;
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
    state.momentum = clampEnergy(state.momentum + scaledEnergyGain(85, gainMultiplier));
    state.confidence = clamp(state.confidence - 12);
    state.risk = clamp(state.risk + scopeRisk(event));
    state.lastEditAt = event.timestamp;
    state.lastActivityAt = event.timestamp;
    state.energyUpdatedAt = event.timestamp;
    state.lastVerificationPassed = false;
    state.completion = null;
    advanceCombo(state, event, 1, 0, startsNewTurn);
  } else if (event.type === "edit-failure") {
    state.phase = "recover";
    state.status = "failed";
    state.currentActivity = "Repairing a failed edit";
    state.lastFailureAt = event.timestamp;
    state.lastActivityAt = event.timestamp;
    state.energyUpdatedAt = event.timestamp;
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
      state.momentum = clampEnergy(state.momentum + scaledEnergyGain(170, gainMultiplier));
      state.confidence = clamp(state.confidence + verificationConfidence(event.category));
      state.risk = clamp(state.risk - 18);
      if (!state.evidence.includes(event.category)) state.evidence.push(event.category);
      advanceCombo(state, event, 2, VERIFICATION_REWARD_HOLD_MS, startsNewTurn, "reward");
      const backsLatestEdit = state.edits > 0 && state.lastEditAt && event.timestamp >= state.lastEditAt;
      const establishesRecord = state.momentum > state.bestMomentum || state.combo > state.bestCombo;
      state.verificationReward = backsLatestEdit ? (establishesRecord ? "record" : "evidence") : "confirmation";
      state.verificationRewardAt = event.timestamp;
      state.lastActivityAt = event.timestamp;
      state.energyUpdatedAt = event.timestamp;
    } else {
      state.phase = "recover";
      state.status = "failed";
      state.currentActivity = `${event.category} failed — recovering`;
      state.lastFailureAt = event.timestamp;
      state.failedVerifications += 1;
      state.momentum = clampEnergy(state.momentum - 120);
      state.confidence = clamp(state.confidence - 28);
      state.risk = clamp(state.risk + 24);
      state.verificationReward = null;
      state.verificationRewardAt = null;
      state.lastActivityAt = event.timestamp;
      state.energyUpdatedAt = event.timestamp;
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
    state.lastActivityAt = event.timestamp;
    state.energyUpdatedAt = event.timestamp;
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
