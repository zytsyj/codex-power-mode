import { refreshDelayForState } from "./refresh-cadence.mjs";

const canvas = document.querySelector("#effects");
const context = canvas.getContext("2d");
const element = (id) => document.querySelector(`#${id}`);
const elements = Object.fromEntries(["hud", "momentum", "momentum-meter", "power-label", "combo-meter", "combo-count", "combo-bar", "combo-status"].map((id) => [id, element(id)]));
const parameters = new URLSearchParams(location.search);
const requestedLanguage = parameters.get("lang") || "auto";
const chinese = requestedLanguage === "zh-CN" || requestedLanguage === "auto" && navigator.language.toLowerCase().startsWith("zh");
const idleBehavior = ["hide", "orb"].includes(parameters.get("idle")) ? parameters.get("idle") : "hide";
const autoHideDelayMs = Math.max(0, Math.min(6_000, Number(parameters.get("hideDelay") ?? 2_000) || 0));
const reducedMotion = parameters.get("motion") === "reduced" || matchMedia("(prefers-reduced-motion: reduce)").matches;
const preset = parameters.get("preset") === "arcade" ? "arcade" : "focus";
const previewPhase = parameters.get("phase");
const previewCombo = parameters.get("combo");
const previewEnergy = parameters.get("energy");
const previewEvent = parameters.get("event");
const previewCompletion = parameters.get("completion");
const previewReward = ["confirmation", "evidence", "record"].includes(parameters.get("reward")) ? parameters.get("reward") : null;
const previewOffline = parameters.get("connection") === "offline";
const previewStale = parameters.get("age") === "stale";
const intensity = preset === "arcade" ? 1.75 : 1;
const finalStateHoldMs = 3_000;
const comboLostMs = 3_200;
const comboRelinkFeedbackMs = 1_600;
const momentumReturnMs = 4_000;
const abandonedActivityMs = 5 * 60_000;
const recoveryTimeoutMs = 15_000;
const effectBudget = preset === "arcade"
  ? { particles: 560, rings: 18, scans: 8 }
  : { particles: 280, rings: 10, scans: 4 };
const particles = [];
const rings = [];
const scans = [];
let state = {};
let scale = devicePixelRatio || 1;
let collapseTimer;
let effectsFrame = null;
let presentationTimer = null;
let presentationTicks = 0;
let hudVisibleUntil = Date.now() + 1800;
let connectionOnline = false;
let effectGeneration = 0;
let sessionTransitionUntil = 0;
let visualPhase = null;
let visualComboStage = null;
let visualEnergyLevel = null;
let visualPhaseEnteredAt = parameters.get("tempo") === "settled" ? Date.now() - 20_000 : Date.now();

const copy = {
  power: ["POWER", "能量"], online: ["ONLINE", "在线"], reconnecting: ["RECONNECTING", "重新连接"], preview: ["PREVIEW", "预览"],
  observe: ["OBSERVE", "观察"], act: ["ACT", "执行"], verify: ["VERIFY", "验证"], wait: ["WAIT", "等待"], recover: ["RECOVER", "恢复"], complete: ["COMPLETE", "完成"], idle: ["IDLE", "待机"],
  cancelled: ["CANCELLED", "已取消"], unverified: ["UNVERIFIED", "未验证"], hold: ["HOLD", "保持"], waiting: ["WAIT", "等待"], link: ["LINK", "续连"], done: ["DONE", "完成"], lost: ["LOST", "断连"], ready: ["READY", "就绪"],
  charging: ["CHARGE", "蓄能"], flow: ["FLOW", "流动"], surge: ["SURGE", "高能"], overdrive: ["OVERDRIVE", "过载"],
  building: ["BUILD", "蓄连"], linked: ["LINK", "续连"], chain: ["CHAIN", "连锁"], critical: ["BREAK", "将断"], reward: ["BOOST", "奖励"], confirmed: ["CHECK", "确认"], record: ["RECORD", "纪录"], relinked: ["RELINK", "重连"],
  approval: ["Your approval is needed", "等待你的授权"], approvalDenied: ["Approval was not granted", "未获得授权"], verifyRecommended: ["Run verification before relying on these changes", "建议验证后再使用这些修改"], noChanges: ["No code changes were made", "没有代码修改"], recovering: ["Confidence dropped; repairing the latest change", "可信度下降，正在修复最近的修改"], verified: ["Latest changes are backed by evidence", "最新修改已有验证证据"], checking: ["Building confidence in the change", "正在验证修改"], acting: ["Applying a scoped change", "正在执行修改"], understandingTitle: ["UNDERSTANDING REQUEST", "理解需求"], understanding: ["Understanding your request", "正在理解你的需求"], observing: ["Reading and understanding context", "正在读取并理解上下文"], standby: ["Waiting for Codex activity", "等待 Codex 活动"],
  taskSwitched: ["TASK SWITCHED", "任务已切换"], followingTask: ["Following the newly active Codex task", "正在跟随新的 Codex 任务"],
  newBest: ["NEW PERSONAL BEST", "刷新个人纪录"]
};
const t = (key) => copy[key]?.[chinese ? 1 : 0] ?? key;

document.body.dataset.preset = preset;
document.body.dataset.motion = reducedMotion ? "reduced" : "full";
document.documentElement.lang = chinese ? "zh-CN" : "en";
elements["power-label"].textContent = t("power");
if (parameters.get("preview") === "light") document.body.dataset.preview = "light";

const palette = {
  observe: "#75dfff", act: "#a886ff", verify: "#62e3ad",
  wait: "#ffc568", recover: "#ff6486", complete: "#72e9bf", idle: "#b7bec9"
};
const previewMode = previewPhase in palette;

if (previewMode) {
  document.body.dataset.previewState = "true";
  const cancelledComplete = previewPhase === "complete" && previewCompletion === "cancelled";
  const unverifiedComplete = previewPhase === "complete" && previewCompletion === "unverified";
  const noChangeComplete = previewPhase === "complete" && previewCompletion === "no-change";
  const verifiedComplete = previewPhase === "complete" && !cancelledComplete && !unverifiedComplete && !noChangeComplete;
  const incompleteOutcome = cancelledComplete || unverifiedComplete;
  const recoveryPreview = previewPhase === "recover";
  const previewNow = Date.now();
  const comboBroken = previewCombo === "lost";
  const comboHolding = previewCombo === "hold";
  const comboCritical = previewCombo === "critical";
  const comboRelinked = previewCombo === "relink";
  const previewMomentum = { charging: 18, flow: 38, surge: 64, overdrive: 88 }[previewEnergy] ?? (verifiedComplete ? 100 : 72);
  render({
    phase: previewPhase,
    status: cancelledComplete ? "cancelled" : unverifiedComplete ? "unverified" : previewPhase === "wait" ? "needs-attention" : previewPhase === "recover" ? "failed" : "ready",
    momentum: previewMomentum,
    confidence: verifiedComplete ? 100 : 84,
    riskLevel: previewPhase === "recover" ? "high" : "low",
    completion: cancelledComplete ? "cancelled" : unverifiedComplete ? "unverified" : noChangeComplete ? "no-change" : verifiedComplete ? "verified" : undefined,
    evidence: verifiedComplete ? ["test", "build"] : previewReward === "confirmation" ? [] : previewReward ? ["test"] : [],
    combo: comboBroken || recoveryPreview || previewPhase === "complete" && !verifiedComplete ? 0 : comboRelinked ? 1 : verifiedComplete ? 12 : 8,
    bestCombo: verifiedComplete ? 12 : 8,
    comboStatus: comboBroken || recoveryPreview || incompleteOutcome ? "broken" : noChangeComplete ? "idle" : comboHolding ? "holding" : previewReward ? "reward" : verifiedComplete ? "complete" : "decaying",
    comboLastAt: new Date(previewNow).toISOString(),
    comboHoldUntil: comboBroken ? null : new Date(previewNow + (comboHolding ? 60_000 : comboCritical ? -10_000 : 0)).toISOString(),
    comboExpiresAt: comboBroken || previewPhase === "complete" && !verifiedComplete ? null : new Date(previewNow + (comboHolding ? 72_000 : comboCritical ? 2_500 : 12_000)).toISOString(),
    comboBrokenAt: comboBroken || recoveryPreview || incompleteOutcome ? new Date(previewNow - (previewStale ? 30_000 : 0)).toISOString() : null,
    comboRelinkedAt: comboRelinked ? new Date(previewNow).toISOString() : null,
    verificationReward: previewReward,
    verificationRewardAt: previewReward ? new Date(previewNow).toISOString() : null,
    lastFailureAt: previewPhase === "recover" ? new Date(previewNow - (previewStale ? 30_000 : 0)).toISOString() : null,
    currentActivity: cancelledComplete ? "Approval was not granted" : unverifiedComplete ? "Completed — verification recommended" : noChangeComplete ? "Turn complete" : previewPhase === "wait" ? "Waiting for your approval" : previewEvent === "prompt-submit" ? "Understanding request" : previewEvent === "edit-failure" ? "Repairing a failed edit" : previewPhase === "recover" ? "Repairing failed verification" : verifiedComplete ? "Completed with evidence" : "Codex activity preview"
  });
  if (previewOffline) setConnection(false, false);
  else {
    document.body.dataset.connection = "preview";
  }
  expand(0);
  if (previewEvent === "edit-failure") setTimeout(() => react({ type: "edit-failure", state }), 0);
  if (previewEvent === "prompt-submit") setTimeout(() => react({ type: "activity-start", phase: "observe", toolGroup: "prompt", state }), 0);
  if (previewEvent === "activity-start") setTimeout(() => react({ type: "activity-start", phase: previewPhase, state }), 0);
  if (previewEvent === "verification") setTimeout(() => react({ type: "verification", phase: "verify", category: "test", success: true, state }), 0);
  if (previewEvent === "session-switch") setTimeout(() => react({ type: "activity-start", phase: previewPhase, state, sessionTransition: { previousSessionId: "preview-a", currentSessionId: "preview-b" } }), 0);
  if (previewEvent === "permission-request") setTimeout(() => react({ type: "permission-request", state }), 0);
  if (previewEvent === "turn-stop" && previewPhase === "complete") setTimeout(() => react({ type: "turn-stop", state }), 0);
}

function setConnection(connected, announce = true) {
  connectionOnline = connected;
  document.body.dataset.connection = connected ? "online" : "offline";
  if (announce) expand(connected ? 1800 : 3200);
  requestPresentationTick();
}

function resize() {
  scale = devicePixelRatio || 1;
  canvas.width = innerWidth * scale;
  canvas.height = innerHeight * scale;
  context.setTransform(scale, 0, 0, scale, 0, 0);
}

function reactorOrigin() {
  const rect = document.querySelector(".reactor").getBoundingClientRect();
  return { x: rect.left + rect.width / 2, y: rect.top + rect.height / 2 };
}

function workOrigin() {
  return { x: innerWidth * (.28 + Math.random() * .30), y: innerHeight * (.28 + Math.random() * .44) };
}

function expand(duration = 2100) {
  clearTimeout(collapseTimer);
  elements.hud.classList.remove("collapsed");
  hudVisibleUntil = Math.max(hudVisibleUntil, Date.now() + Math.max(0, duration));
  if (duration > 0) collapseTimer = setTimeout(() => elements.hud.classList.add("collapsed"), duration);
}

function burst(color, amount, power = 1, mode = "radial", start = reactorOrigin()) {
  if (reducedMotion) return;
  const count = Math.min(220, Math.round(amount * intensity));
  for (let index = 0; index < count; index += 1) {
    const evidenceLane = index % 4;
    const gateSide = index % 2 === 0 ? -1 : 1;
    const gateLane = Math.floor(index / 2) % 5 - 2;
    const repairSide = index % 2 === 0 ? -1 : 1;
    const repairLane = Math.floor(index / 2) % 4 - 1.5;
    const angle = mode === "left"
      ? Math.PI - .34 + Math.random() * .68
      : mode === "outward" || mode === "fragments"
      ? Math.PI - .62 + Math.random() * 1.24
      : Math.random() * Math.PI * 2;
    const focusRadius = 52 + Math.random() * 150;
    const source = mode === "focus"
      ? { x: start.x + Math.cos(angle) * focusRadius, y: start.y + Math.sin(angle) * focusRadius }
      : mode === "repair"
      ? { x: start.x + repairSide * (42 + Math.random() * 145), y: start.y + repairLane * 17 + (Math.random() - .5) * 10 }
      : mode === "gate"
      ? { x: start.x + gateSide * (66 + Math.random() * 150), y: start.y + gateLane * 10 + (Math.random() - .5) * 3 }
      : mode === "evidence"
      ? { x: start.x - 78 - Math.random() * 190, y: start.y + (evidenceLane - 1.5) * 18 + (Math.random() - .5) * 6 }
      : mode === "inward" ? workOrigin() : start;
    const distance = mode === "inward" ? 18 + Math.random() * 90 : 0;
    const x = source.x + Math.cos(angle) * distance;
    const y = source.y + Math.sin(angle) * distance;
    const speed = (1.1 + Math.random() * 4.7) * power * intensity;
    const approachFrames = 24 + Math.random() * 12;
    particles.push({
      x, y,
      vx: mode === "focus" ? (start.x - x) / (26 + Math.random() * 9) : mode === "repair" ? (start.x - x) / (24 + Math.random() * 8) : mode === "gate" ? (start.x + gateSide * 38 - x) / 18 : mode === "evidence" ? (start.x - x) / approachFrames : mode === "inward" ? (start.x - x) / (28 + Math.random() * 14) : Math.cos(angle) * speed,
      vy: mode === "focus" ? (start.y - y) / (26 + Math.random() * 9) : mode === "repair" ? (start.y - y) / (24 + Math.random() * 8) : mode === "gate" ? (start.y + gateLane * 7 - y) / 18 : mode === "evidence" ? (start.y - y) / approachFrames : mode === "inward" ? (start.y - y) / (28 + Math.random() * 14) : Math.sin(angle) * speed,
      life: 34 + Math.random() * 44,
      maxLife: 78,
      size: .8 + Math.random() * (preset === "arcade" ? 3.2 : 2.1),
      color,
      drag: mode === "inward" || mode === "evidence" || mode === "repair" || mode === "focus" ? 1.012 : mode === "gate" ? .995 : .985,
      square: mode === "fragments" || mode === "left" || mode === "evidence" || mode === "gate" || mode === "repair"
    });
  }
  scheduleEffectsFrame();
}

function ring(color, power = 1, start = reactorOrigin()) {
  if (!reducedMotion) {
    rings.push({ ...start, radius: 8, life: 38, maxLife: 38, color, speed: 4.4 * power * intensity });
    scheduleEffectsFrame();
  }
}

function scan(color) {
  if (reducedMotion) return;
  const start = reactorOrigin();
  scans.push({ x: start.x - 18, y: start.y, width: Math.min(innerWidth * .72, start.x - 48), life: 58, maxLife: 58, color });
  scheduleEffectsFrame();
}

function scheduleEffectsFrame() {
  if (effectsFrame === null) effectsFrame = requestAnimationFrame(frame);
}

function frame() {
  effectsFrame = null;
  if (particles.length > effectBudget.particles) particles.splice(0, particles.length - effectBudget.particles);
  if (rings.length > effectBudget.rings) rings.splice(0, rings.length - effectBudget.rings);
  if (scans.length > effectBudget.scans) scans.splice(0, scans.length - effectBudget.scans);
  context.clearRect(0, 0, innerWidth, innerHeight);
  context.globalCompositeOperation = "lighter";
  for (let index = scans.length - 1; index >= 0; index -= 1) {
    const item = scans[index];
    item.life -= 1;
    if (item.life <= 0) { scans.splice(index, 1); continue; }
    const progress = 1 - item.life / item.maxLife;
    const head = item.x - item.width * progress;
    const gradient = context.createLinearGradient(head, 0, head + 120, 0);
    gradient.addColorStop(0, item.color); gradient.addColorStop(1, "transparent");
    context.globalAlpha = Math.sin(progress * Math.PI) * .36;
    context.fillStyle = gradient;
    context.fillRect(head, item.y, 120, 1.2);
    context.fillRect(head, item.y - 10, 1, 21);
  }
  for (let index = rings.length - 1; index >= 0; index -= 1) {
    const item = rings[index];
    item.radius += item.speed; item.life -= 1;
    if (item.life <= 0) { rings.splice(index, 1); continue; }
    context.globalAlpha = item.life / item.maxLife * .48;
    context.strokeStyle = item.color;
    context.lineWidth = preset === "arcade" ? 1.7 : 1;
    context.beginPath(); context.arc(item.x, item.y, item.radius, 0, Math.PI * 2); context.stroke();
  }
  for (let index = particles.length - 1; index >= 0; index -= 1) {
    const item = particles[index];
    item.x += item.vx; item.y += item.vy;
    item.vx *= item.drag; item.vy *= item.drag; item.life -= 1;
    if (item.life <= 0) { particles.splice(index, 1); continue; }
    context.globalAlpha = Math.min(.9, item.life / 18);
    context.fillStyle = item.color;
    if (item.square) context.fillRect(item.x - item.size, item.y - item.size, item.size * 2.4, item.size * 1.25);
    else { context.beginPath(); context.arc(item.x, item.y, item.size, 0, Math.PI * 2); context.fill(); }
  }
  context.globalAlpha = 1;
  if (particles.length || rings.length || scans.length) scheduleEffectsFrame();
}

function statusCopy(next) {
  if (next.phase === "idle") return t("standby");
  if (next.currentActivity === "Understanding request") return t("understanding");
  if (next.phase === "wait") return t("approval");
  if (next.completion === "cancelled") return t("approvalDenied");
  if (next.completion === "unverified") return t("verifyRecommended");
  if (next.completion === "no-change") return t("noChanges");
  if (next.phase === "recover") return t("recovering");
  if (next.phase === "complete" && next.completion === "verified") return t("verified");
  if (next.phase === "complete") return t("verifyRecommended");
  if (next.phase === "verify") return t("checking");
  if (next.phase === "act") return t("acting");
  return t("observing");
}

function presentationAt(next, now = Date.now()) {
  const explicitStopAt = Date.parse(next.turnStoppedAt);
  const lastActivityAt = Date.parse(next.lastActivityAt);
  const lastFailureAt = Date.parse(next.lastFailureAt ?? next.lastVerificationAt ?? next.lastActivityAt);
  const canSettleAbandoned = ["observe", "act", "verify"].includes(next.phase) && next.status !== "needs-attention" && next.status !== "failed";
  const canSettleRecovery = next.phase === "recover" && next.status === "failed" && Number.isFinite(lastFailureAt);
  const stoppedAt = Number.isFinite(explicitStopAt)
    ? explicitStopAt
    : canSettleRecovery
      ? lastFailureAt + recoveryTimeoutMs
      : canSettleAbandoned && Number.isFinite(lastActivityAt)
        ? lastActivityAt + abandonedActivityMs
        : Number.NaN;
  const momentum = Math.max(0, Math.min(100, next.momentum ?? 0));
  if (!Number.isFinite(stoppedAt)) return { ...next, momentum, idle: false, settled: false, returning: false, idleAt: null, settledAt: null };
  const explicitBreak = Date.parse(next.comboBrokenAt);
  const naturalBreak = Date.parse(next.comboExpiresAt);
  const disconnectedAt = Number.isFinite(explicitBreak) ? explicitBreak : naturalBreak;
  const comboEnd = Number.isFinite(disconnectedAt) ? disconnectedAt + comboLostMs : 0;
  const idleAt = Math.max(stoppedAt + finalStateHoldMs, comboEnd);
  const settledAt = idleAt + momentumReturnMs;
  if (now < idleAt) return { ...next, momentum, idle: false, settled: false, returning: true, idleAt, settledAt };
  const progress = Math.max(0, Math.min(1, (now - idleAt) / momentumReturnMs));
  return {
    ...next,
    phase: "idle",
    status: "ready",
    completion: null,
    currentActivity: t("standby"),
    momentum: Math.round(momentum * (1 - progress)),
    idle: true,
    settled: progress >= 1,
    returning: progress < 1,
    idleAt,
    settledAt
  };
}

function comboProgressAt(next, now = Date.now()) {
  if (!next.combo || !next.comboExpiresAt) return 0;
  const holdUntil = Date.parse(next.comboHoldUntil || next.comboLastAt);
  const expiresAt = Date.parse(next.comboExpiresAt);
  if (![now, holdUntil, expiresAt].every(Number.isFinite)) return 0;
  if (now <= holdUntil) return 1;
  if (now >= expiresAt) return 0;
  return Math.max(0, Math.min(1, (expiresAt - now) / Math.max(1, expiresAt - holdUntil)));
}

function energyLevelAt(momentum) {
  if (momentum <= 0) return "idle";
  if (momentum < 25) return "charging";
  if (momentum < 50) return "flow";
  if (momentum < 75) return "surge";
  return "overdrive";
}

function energyRankAt(level) {
  return { idle: 0, charging: 1, flow: 2, surge: 3, overdrive: 4 }[level] ?? 0;
}

function reactToEnergyTransition(level) {
  if (reducedMotion || level === "idle") return;
  const start = reactorOrigin();
  const color = level === "overdrive" ? "#ffd66b" : level === "surge" ? "#a987ff" : "#75dfff";
  document.body.classList.remove("energy-upgrade-charging", "energy-upgrade-flow", "energy-upgrade-surge", "energy-upgrade-overdrive");
  void document.body.offsetWidth;
  document.body.classList.add(`energy-upgrade-${level}`);
  if (level === "charging") {
    ring(color, preset === "arcade" ? .42 : .24, start);
  } else if (level === "flow") {
    ring(color, preset === "arcade" ? .72 : .42, start);
    burst(color, preset === "arcade" ? 34 : 16, .48, "inward", start);
  } else if (level === "surge") {
    ring(color, preset === "arcade" ? 1.18 : .68, start);
    burst(color, preset === "arcade" ? 58 : 26, .72, "inward", start);
    if (preset === "arcade") scheduleEffect(160, effectGeneration, () => ring("#75dfff", .82, start));
  } else {
    ring(color, preset === "arcade" ? 1.72 : .92, start);
    burst(color, preset === "arcade" ? 86 : 38, preset === "arcade" ? 1.0 : .68, "radial", start);
    scheduleEffect(180, effectGeneration, () => ring("#75dfff", preset === "arcade" ? 1.28 : .62, start));
  }
}

function comboStageAt(next, progress, status, now = Date.now()) {
  if (status === "broken") return "lost";
  if (status === "idle") return "idle";
  if (next.comboStatus === "reward" || next.comboStatus === "complete") {
    if (next.verificationReward === "record") return "record";
    if (next.verificationReward === "confirmation") return "confirmed";
    return "reward";
  }
  const relinkedAt = Date.parse(next.comboRelinkedAt);
  if (Number.isFinite(relinkedAt) && now < relinkedAt + comboRelinkFeedbackMs) return "relinked";
  if (progress <= .25) return "critical";
  if ((next.combo ?? 0) < 3) return "building";
  if ((next.combo ?? 0) < 6) return "linked";
  return "chain";
}

function renderCombo(now = Date.now()) {
  const progress = comboProgressAt(state, now);
  const active = (state.combo ?? 0) > 0 && progress > 0;
  const explicitBreak = Date.parse(state.comboBrokenAt);
  const naturalBreak = Date.parse(state.comboExpiresAt);
  const disconnectedAt = Number.isFinite(explicitBreak) ? explicitBreak : naturalBreak;
  const recentlyLost = Number.isFinite(disconnectedAt) && now < disconnectedAt + 3_200;
  const status = active ? (state.comboStatus ?? "decaying") : recentlyLost ? "broken" : "idle";
  const stage = comboStageAt(state, progress, status, now);
  elements["combo-count"].textContent = active ? `${state.combo}×` : recentlyLost ? "—" : "0×";
  elements["combo-bar"].style.transform = `scaleX(${progress.toFixed(3)})`;
  elements["combo-meter"].style.setProperty("--combo-progress", `${(progress * 360).toFixed(1)}deg`);
  elements["combo-status"].textContent = t(stage);
  document.body.dataset.comboStatus = status;
  document.body.dataset.comboStage = stage;
  if (stage !== visualComboStage) {
    if (visualComboStage !== null || previewMode) reactToComboTransition(stage);
    visualComboStage = stage;
  }
  updateIdleVisibility(now, active || recentlyLost, presentationAt(state, now));
}

function reactToComboTransition(stage) {
  if (reducedMotion || !["lost", "relinked"].includes(stage)) return;
  const start = reactorOrigin();
  const color = stage === "lost" ? "#ff5477" : "#65e9de";
  document.body.classList.remove("combo-break-kick", "combo-relink-kick");
  void document.body.offsetWidth;
  document.body.classList.add(stage === "lost" ? "combo-break-kick" : "combo-relink-kick");
  ring(color, stage === "lost" ? (preset === "arcade" ? .82 : .42) : (preset === "arcade" ? .72 : .38), start);
  burst(color, stage === "lost" ? (preset === "arcade" ? 42 : 20) : (preset === "arcade" ? 36 : 18), .58, stage === "lost" ? "fragments" : "inward", start);
}

function updateIdleVisibility(now = Date.now(), comboVisible = false, presented = presentationAt(state, now)) {
  if (previewMode) return;
  const urgent = presented.phase === "wait" || presented.phase === "recover" || presented.status === "needs-attention" || presented.status === "failed";
  const working = presented.status === "working";
  const terminalReturning = presented.returning;
  const idleGrace = presented.settled && Number.isFinite(presented.settledAt) && now < presented.settledAt + autoHideDelayMs;
  document.body.dataset.idleGrace = presented.settled ? (idleGrace ? "active" : "expired") : "pending";
  const visible = idleBehavior !== "hide" || !connectionOnline || urgent || working || comboVisible || terminalReturning || idleGrace || now < hudVisibleUntil;
  elements.hud.classList.toggle("idle-hidden", !visible);
}

function renderPresentation(now = Date.now()) {
  const presented = presentationAt(state, now);
  const phase = presented.phase ?? "observe";
  const momentum = presented.momentum ?? 0;
  const energyLevel = energyLevelAt(momentum);
  if (phase !== visualPhase) {
    visualPhase = phase;
    visualPhaseEnteredAt = parameters.get("tempo") === "settled" ? now - 20_000 : now;
  }
  const phaseAge = now - visualPhaseEnteredAt;
  const settledTempo = phase === "wait" ? phaseAge >= 12_000 : phase === "recover" ? phaseAge >= 10_000 : false;
  document.body.dataset.phase = phase;
  document.body.dataset.status = presented.status ?? "ready";
  document.body.dataset.completion = presented.completion ?? "none";
  document.body.dataset.activity = presented.currentActivity === "Understanding request" ? "understanding" : "context";
  document.body.dataset.energyLevel = energyLevel;
  if (energyLevel !== visualEnergyLevel) {
    if ((visualEnergyLevel !== null && energyRankAt(energyLevel) > energyRankAt(visualEnergyLevel)) || (previewMode && visualEnergyLevel === null)) reactToEnergyTransition(energyLevel);
    visualEnergyLevel = energyLevel;
  }
  document.body.dataset.verificationReward = presented.verificationReward ?? "none";
  document.body.dataset.phaseTempo = settledTempo ? "settled" : "alert";
  elements.momentum.textContent = momentum;
  elements["momentum-meter"].style.setProperty("--progress", `${momentum * 3.6}deg`);
  elements["power-label"].textContent = orbActivityCopy(presented);
}

function orbActivityCopy(presented) {
  if (!connectionOnline && !previewMode) return chinese ? "重连中" : "RECONNECT";
  if (presented.idle || presented.phase === "idle") return t("idle");
  if (presented.status === "needs-attention" || presented.phase === "wait") return chinese ? "等待授权" : "APPROVAL";
  if (presented.status === "failed" || presented.phase === "recover") return chinese ? "修复中" : "RECOVER";
  if (presented.completion === "verified") return chinese ? "已验证" : "VERIFIED";
  if (presented.completion === "unverified") return chinese ? "待验证" : "CHECK";
  if (presented.currentActivity === "Understanding request") return chinese ? "理解需求" : "THINKING";
  if (presented.phase === "observe") return chinese ? "读取上下文" : "READING";
  if (presented.phase === "act") return chinese ? "修改中" : "CHANGE";
  if (presented.phase === "verify") return chinese ? "验证中" : "VERIFY";
  return chinese ? "工作中" : "WORKING";
}

function render(next = state) {
  state = { ...state, ...next };
  renderPresentation();
  renderCombo();
  requestPresentationTick();
}

function flashAt(start, strength = .14) {
  document.body.style.setProperty("--flash-x", `${start.x}px`);
  document.body.style.setProperty("--flash-y", `${start.y}px`);
  document.body.style.setProperty("--flash-alpha", strength);
  document.body.classList.remove("flash");
  void document.body.offsetWidth;
  document.body.classList.add("flash");
}

function presentationRefreshDelay(now = Date.now()) {
  const presented = presentationAt(state, now);
  const holdUntil = Date.parse(state.comboHoldUntil || state.comboLastAt);
  const expiresAt = Date.parse(state.comboExpiresAt);
  const comboChanging = (state.combo ?? 0) > 0
    && Number.isFinite(expiresAt)
    && now > (Number.isFinite(holdUntil) ? holdUntil : 0)
    && now < expiresAt;
  const momentumChanging = presented.returning
    && Number.isFinite(presented.idleAt)
    && now >= presented.idleAt;
  return refreshDelayForState({
    previewMode,
    connectionOnline,
    hudHidden: elements.hud.classList.contains("idle-hidden"),
    comboChanging,
    momentumChanging
  });
}

function schedulePresentationTick(delay) {
  if (presentationTimer !== null) clearTimeout(presentationTimer);
  if (delay === null) {
    presentationTimer = null;
    document.body.dataset.refreshMode = "sleep";
    return;
  }
  document.body.dataset.refreshMode = delay <= 100 ? "active" : "heartbeat";
  presentationTimer = setTimeout(runPresentationTick, delay);
}

function requestPresentationTick() {
  schedulePresentationTick(0);
}

function runPresentationTick() {
  presentationTimer = null;
  const now = Date.now();
  presentationTicks += 1;
  document.body.dataset.refreshTicks = String(presentationTicks);
  renderPresentation(now);
  renderCombo(now);
  schedulePresentationTick(presentationRefreshDelay(now));
}

function scheduleEffect(delay, generation, effect) {
  setTimeout(() => {
    if (generation === effectGeneration) effect();
  }, delay);
}

function react(event) {
  const generation = ++effectGeneration;
  const switchedSession = Boolean(event.sessionTransition);
  if (switchedSession) {
    particles.length = 0;
    rings.length = 0;
    scans.length = 0;
    context.clearRect(0, 0, innerWidth, innerHeight);
    sessionTransitionUntil = Date.now() + 1800;
  }
  render(event.state);
  const phase = event.state?.phase ?? event.phase ?? "observe";
  const color = event.state?.completion === "cancelled" ? "#ffad66" : event.state?.completion === "unverified" ? "#ffe07a" : palette[phase];
  const start = reactorOrigin();
  const completion = event.state?.completion;
  const quietCompletion = event.type === "turn-stop" && completion === "no-change";
  const momentumPower = .7 + Math.min(100, event.state?.momentum ?? 0) / 125;
  expand(phase === "wait" || phase === "recover" ? 0 : phase === "complete" ? 3200 : 2100);
  const flashStrength = event.type !== "turn-stop" ? .14 : completion === "verified" ? (preset === "arcade" ? .18 : .09) : completion === "cancelled" ? .08 : completion === "unverified" ? .10 : .035;
  flashAt(start, flashStrength);
  if (!quietCompletion) {
    document.body.classList.remove("event-kick");
    void document.body.offsetWidth;
    document.body.classList.add("event-kick");
  }

  if (switchedSession) {
    ring("#75dfff", .78, start);
    burst("#75dfff", 24, .55, "inward", start);
    scheduleEffect(180, generation, () => ring("#a886ff", .62, start));
    return;
  }

  if (event.type === "activity-start" && phase === "observe") {
    if (event.toolGroup === "prompt") {
      burst(color, 42, .72, "focus", start); ring(color, .44, start);
      if (preset === "arcade") scheduleEffect(150, generation, () => burst(color, 24, .56, "focus", start));
    } else {
      scan(color);
      if (preset === "arcade") scheduleEffect(130, generation, () => scan(color));
    }
  } else if (event.type === "activity-start" && phase === "verify") {
    burst(color, 38, .62, "evidence", start); ring(color, .48, start);
    if (preset === "arcade") scheduleEffect(180, generation, () => ring(color, .34, start));
  } else if (event.type === "activity-start") {
    burst(color, 26, .72, "left", start);
    if (preset === "arcade") scheduleEffect(110, generation, () => burst(color, 20, .6, "left", start));
  } else if (event.type === "permission-request") {
    burst(color, 34, .82, "gate", start); ring(color, .48, start);
    scheduleEffect(260, generation, () => { burst(color, 24, .68, "gate", start); ring(color, .36, start); });
  } else if (event.type === "edit") {
    burst(color, 38, momentumPower, "outward", start); ring(color, momentumPower, start);
  } else if (event.type === "edit-failure") {
    burst(color, 74, 1.15, "fragments", start); ring(color, .95, start);
    scheduleEffect(180, generation, () => ring(color, .62, start));
    scheduleEffect(300, generation, () => burst("#ffadc0", 54, .82, "repair", start));
  } else if (event.type === "verification" && event.success) {
    if (event.state?.verificationReward === "record") {
      ring("#ffd66b", preset === "arcade" ? 2.15 : 1.15, start);
      burst("#ffd66b", preset === "arcade" ? 100 : 48, 1.08, "inward", start);
      scheduleEffect(180, generation, () => { ring("#65e9de", preset === "arcade" ? 1.55 : .72, start); burst("#65e9de", preset === "arcade" ? 72 : 30, .88, "radial", start); });
    } else if (event.state?.verificationReward === "evidence") {
      burst(color, preset === "arcade" ? 76 : 44, momentumPower, "inward", start); ring(color, preset === "arcade" ? 1.45 : .88, start);
      scheduleEffect(240, generation, () => ring(color, preset === "arcade" ? .76 : .4, start));
    } else {
      burst(color, preset === "arcade" ? 42 : 24, .62, "evidence", start); ring(color, preset === "arcade" ? .82 : .46, start);
    }
  } else if (event.type === "verification") {
    burst(color, 52, 1.05, "fragments", start); ring(color, .8, start);
    scheduleEffect(300, generation, () => burst("#ffadc0", 46, .76, "repair", start));
  } else if (event.type === "turn-stop" && event.state?.completion === "cancelled") {
    ring(color, preset === "arcade" ? .92 : .62, start);
    burst(color, preset === "arcade" ? 46 : 22, preset === "arcade" ? .82 : .54, "fragments", start);
    if (preset === "arcade") scheduleEffect(160, generation, () => burst(color, 24, .62, "left", start));
  } else if (event.type === "turn-stop" && event.state?.completion === "unverified") {
    burst(color, preset === "arcade" ? 44 : 24, .56, "inward", start); ring(color, preset === "arcade" ? .82 : .58, start);
    scheduleEffect(240, generation, () => { burst(color, preset === "arcade" ? 30 : 16, .48, "gate", start); if (preset === "arcade") ring(color, .46, start); });
  } else if (event.type === "turn-stop" && event.state?.completion === "no-change") {
    burst(color, preset === "arcade" ? 20 : 12, .36, "focus", start); ring(color, .24, start);
  } else if (event.state?.completion === "verified") {
    if (preset === "arcade") {
      ring(color, 2.4, start); burst(color, 95, 1.2, "radial", start);
      scheduleEffect(180, generation, () => { ring("#a886ff", 1.9, start); burst("#a886ff", 52, .9, "radial", start); });
      scheduleEffect(360, generation, () => { ring("#75dfff", 1.55, start); burst("#75dfff", 38, .78, "radial", start); });
    } else {
      burst(color, 34, .62, "inward", start); ring(color, .92, start);
    }
  }
}

if (!previewMode) {
  setConnection(false, false);
  fetch("/api/browser-token")
    .then((response) => response.ok ? response.json() : Promise.reject(new Error("Unauthorized")))
    .then(({ token }) => {
      const stream = new EventSource(`/api/stream?token=${encodeURIComponent(token)}`);
      stream.onopen = () => setConnection(true);
      stream.onerror = () => setConnection(false);
      stream.onmessage = ({ data }) => {
        const event = JSON.parse(data);
        if (event.type === "connected") render(event.state);
        else react(event);
      };
    })
    .catch(() => setConnection(false));
}

addEventListener("resize", resize);
resize();
requestPresentationTick();
