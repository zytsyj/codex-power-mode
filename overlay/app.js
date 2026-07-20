const canvas = document.querySelector("#effects");
const context = canvas.getContext("2d");
const element = (id) => document.querySelector(`#${id}`);
const elements = Object.fromEntries(["hud", "connection", "momentum", "momentum-meter", "phase", "event", "status-copy", "confidence", "evidence", "risk-level", "combo-count", "combo-bar", "combo-status"].map((id) => [id, element(id)]));
const parameters = new URLSearchParams(location.search);
const reducedMotion = parameters.get("motion") === "reduced" || matchMedia("(prefers-reduced-motion: reduce)").matches;
const preset = parameters.get("preset") === "arcade" ? "arcade" : "focus";
const previewPhase = parameters.get("phase");
const previewCombo = parameters.get("combo");
const previewEvent = parameters.get("event");
const previewCompletion = parameters.get("completion");
const previewOffline = parameters.get("connection") === "offline";
const intensity = preset === "arcade" ? 1.75 : 1;
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

document.body.dataset.preset = preset;
document.body.dataset.motion = reducedMotion ? "reduced" : "full";
if (parameters.get("preview") === "light") document.body.dataset.preview = "light";

const palette = {
  observe: "#75dfff", act: "#a886ff", verify: "#62e3ad",
  wait: "#ffc568", recover: "#ff6486", complete: "#72e9bf"
};
const previewMode = previewPhase in palette;

if (previewMode) {
  document.body.dataset.previewState = "true";
  const cancelledComplete = previewPhase === "complete" && previewCompletion === "cancelled";
  const unverifiedComplete = previewPhase === "complete" && previewCompletion === "unverified";
  const noChangeComplete = previewPhase === "complete" && previewCompletion === "no-change";
  const verifiedComplete = previewPhase === "complete" && !cancelledComplete && !unverifiedComplete && !noChangeComplete;
  const incompleteOutcome = cancelledComplete || unverifiedComplete;
  const previewNow = Date.now();
  const comboBroken = previewCombo === "lost";
  const comboHolding = previewCombo === "hold";
  render({
    phase: previewPhase,
    status: cancelledComplete ? "cancelled" : unverifiedComplete ? "unverified" : previewPhase === "wait" ? "needs-attention" : previewPhase === "recover" ? "failed" : "ready",
    momentum: verifiedComplete ? 100 : 72,
    confidence: verifiedComplete ? 100 : 84,
    riskLevel: previewPhase === "recover" ? "high" : "low",
    completion: cancelledComplete ? "cancelled" : unverifiedComplete ? "unverified" : noChangeComplete ? "no-change" : verifiedComplete ? "verified" : undefined,
    evidence: verifiedComplete ? ["test", "build"] : [],
    combo: comboBroken || previewPhase === "complete" && !verifiedComplete ? 0 : verifiedComplete ? 12 : 8,
    bestCombo: verifiedComplete ? 12 : 8,
    comboStatus: comboBroken || incompleteOutcome ? "broken" : noChangeComplete ? "idle" : comboHolding ? "holding" : verifiedComplete ? "complete" : "decaying",
    comboLastAt: new Date(previewNow).toISOString(),
    comboHoldUntil: comboBroken ? null : new Date(previewNow + (comboHolding ? 60_000 : 0)).toISOString(),
    comboExpiresAt: comboBroken || previewPhase === "complete" && !verifiedComplete ? null : new Date(previewNow + (comboHolding ? 72_000 : 12_000)).toISOString(),
    comboBrokenAt: comboBroken || incompleteOutcome ? new Date(previewNow).toISOString() : null,
    currentActivity: cancelledComplete ? "Approval was not granted" : unverifiedComplete ? "Completed — verification recommended" : noChangeComplete ? "Turn complete" : previewPhase === "wait" ? "Waiting for your approval" : previewEvent === "edit-failure" ? "Repairing a failed edit" : previewPhase === "recover" ? "Repairing failed verification" : verifiedComplete ? "Completed with evidence" : "Codex activity preview"
  });
  if (previewOffline) setConnection(false, false);
  else {
    document.body.dataset.connection = "preview";
    elements.connection.textContent = "PREVIEW";
  }
  expand(0);
  if (previewEvent === "edit-failure") setTimeout(() => react({ type: "edit-failure", state }), 0);
  if (previewEvent === "turn-stop" && cancelledComplete) setTimeout(() => react({ type: "turn-stop", state }), 0);
  if (previewEvent === "turn-stop" && unverifiedComplete) setTimeout(() => react({ type: "turn-stop", state }), 0);
}

function setConnection(connected, announce = true) {
  document.body.dataset.connection = connected ? "online" : "offline";
  elements.connection.textContent = connected ? "ONLINE" : "RECONNECTING";
  if (announce) expand(connected ? 1800 : 3200);
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
  if (duration > 0) collapseTimer = setTimeout(() => elements.hud.classList.add("collapsed"), duration);
}

function burst(color, amount, power = 1, mode = "radial", start = reactorOrigin()) {
  if (reducedMotion) return;
  const count = Math.min(220, Math.round(amount * intensity));
  for (let index = 0; index < count; index += 1) {
    const angle = mode === "outward" || mode === "fragments"
      ? Math.PI - .62 + Math.random() * 1.24
      : Math.random() * Math.PI * 2;
    const source = mode === "inward" ? workOrigin() : start;
    const distance = mode === "inward" ? 18 + Math.random() * 90 : 0;
    const x = source.x + Math.cos(angle) * distance;
    const y = source.y + Math.sin(angle) * distance;
    const speed = (1.1 + Math.random() * 4.7) * power * intensity;
    particles.push({
      x, y,
      vx: mode === "inward" ? (start.x - x) / (28 + Math.random() * 14) : Math.cos(angle) * speed,
      vy: mode === "inward" ? (start.y - y) / (28 + Math.random() * 14) : Math.sin(angle) * speed,
      life: 34 + Math.random() * 44,
      maxLife: 78,
      size: .8 + Math.random() * (preset === "arcade" ? 3.2 : 2.1),
      color,
      drag: mode === "inward" ? 1.012 : .985,
      square: mode === "fragments"
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
  if (next.phase === "wait") return "Your approval is needed";
  if (next.completion === "cancelled") return "Approval was not granted";
  if (next.completion === "unverified") return "Run verification before relying on these changes";
  if (next.completion === "no-change") return "No code changes were made";
  if (next.phase === "recover") return "Confidence dropped; repairing the latest change";
  if (next.phase === "complete" && next.completion === "verified") return "Latest changes are backed by evidence";
  if (next.phase === "complete") return "Verification is still recommended";
  if (next.phase === "verify") return "Building confidence in the change";
  if (next.phase === "act") return "Applying a scoped change";
  return "Reading and understanding context";
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

function renderCombo(now = Date.now()) {
  const progress = comboProgressAt(state, now);
  const active = (state.combo ?? 0) > 0 && progress > 0;
  const explicitBreak = Date.parse(state.comboBrokenAt);
  const naturalBreak = Date.parse(state.comboExpiresAt);
  const disconnectedAt = Number.isFinite(explicitBreak) ? explicitBreak : naturalBreak;
  const recentlyLost = Number.isFinite(disconnectedAt) && now < disconnectedAt + 3_200;
  const status = active ? (state.comboStatus ?? "decaying") : recentlyLost ? "broken" : "idle";
  const labels = { holding: "HOLD", waiting: "WAIT", decaying: "LINK", complete: "DONE", broken: "LOST", idle: "READY" };
  elements["combo-count"].textContent = `${active ? state.combo : 0}×`;
  elements["combo-bar"].style.transform = `scaleX(${progress.toFixed(3)})`;
  elements["combo-status"].textContent = labels[status] ?? "LINK";
  document.body.dataset.comboStatus = status;
}

function render(next = state) {
  state = { ...state, ...next };
  const phase = state.phase ?? "observe";
  const momentum = state.momentum ?? 0;
  document.body.dataset.phase = phase;
  document.body.dataset.status = state.status ?? "ready";
  document.body.dataset.completion = state.completion ?? "none";
  elements.momentum.textContent = momentum;
  elements["momentum-meter"].style.setProperty("--progress", `${momentum * 3.6}deg`);
  elements.phase.textContent = state.completion === "cancelled" ? "CANCELLED" : state.completion === "unverified" ? "UNVERIFIED" : phase.toUpperCase();
  elements.event.textContent = state.currentActivity ?? "Codex Power ready";
  elements["status-copy"].textContent = statusCopy(state);
  elements.confidence.textContent = `CONF ${state.confidence ?? 0}%`;
  elements.evidence.textContent = state.evidence?.length ? `${state.evidence.join("+").toUpperCase()} ✓` : "NO EVIDENCE";
  const riskLevel = String(state.riskLevel ?? "low");
  elements["risk-level"].textContent = `${riskLevel.toUpperCase()} RISK`;
  elements["risk-level"].dataset.level = riskLevel;
  renderCombo();
}

function flashAt(start) {
  document.body.style.setProperty("--flash-x", `${start.x}px`);
  document.body.style.setProperty("--flash-y", `${start.y}px`);
  document.body.classList.remove("flash");
  void document.body.offsetWidth;
  document.body.classList.add("flash");
}

function react(event) {
  render(event.state);
  const phase = event.state?.phase ?? event.phase ?? "observe";
  const color = event.state?.completion === "cancelled" ? "#ffad66" : event.state?.completion === "unverified" ? "#ffe07a" : palette[phase];
  const start = reactorOrigin();
  const momentumPower = .7 + Math.min(100, event.state?.momentum ?? 0) / 125;
  expand(phase === "wait" || phase === "recover" ? 0 : phase === "complete" ? 3200 : 2100);
  flashAt(start);
  document.body.classList.remove("event-kick");
  void document.body.offsetWidth;
  document.body.classList.add("event-kick");

  if (event.type === "activity-start" && phase === "observe") {
    scan(color);
    if (preset === "arcade") setTimeout(() => scan(color), 130);
  } else if (event.type === "activity-start" && phase === "verify") {
    burst(color, 34, .55, "inward", start); ring(color, .55, start);
  } else if (event.type === "activity-start") {
    burst(color, 18, .55, "outward", start);
  } else if (event.type === "permission-request") {
    ring(color, .65, start); setTimeout(() => ring(color, .65, start), 320);
  } else if (event.type === "edit") {
    burst(color, 38, momentumPower, "outward", start); ring(color, momentumPower, start);
  } else if (event.type === "edit-failure") {
    burst(color, 74, 1.15, "fragments", start); ring(color, .95, start);
    setTimeout(() => ring(color, .62, start), 180);
  } else if (event.type === "verification" && event.success) {
    burst(color, 62, momentumPower, "inward", start); ring(color, 1.25, start);
    setTimeout(() => burst(color, 38, .85, "radial", start), 280);
  } else if (event.type === "verification") {
    burst(color, 52, 1.05, "fragments", start); ring(color, .8, start);
  } else if (event.type === "turn-stop" && event.state?.completion === "cancelled") {
    ring(color, .78, start); setTimeout(() => ring(color, .52, start), 190);
  } else if (event.type === "turn-stop" && event.state?.completion === "unverified") {
    ring(color, .68, start);
  } else if (event.state?.completion === "verified") {
    ring(color, 2.4, start); burst(color, 95, 1.2, "radial", start);
    setTimeout(() => { ring("#a886ff", 1.9, start); burst("#a886ff", 52, .9, "radial", start); }, 180);
  }
}

if (!previewMode) {
  const stream = new EventSource("/api/stream");
  setConnection(false, false);
  stream.onopen = () => setConnection(true);
  stream.onerror = () => setConnection(false);
  stream.onmessage = ({ data }) => {
    const event = JSON.parse(data);
    if (event.type === "connected") render(event.state);
    else react(event);
  };
}

addEventListener("resize", resize);
resize();
setInterval(() => renderCombo(), 100);
