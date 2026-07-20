const canvas = document.querySelector("#effects");
const context = canvas.getContext("2d");
const element = (id) => document.querySelector(`#${id}`);
const elements = Object.fromEntries(["hud", "connection", "momentum", "momentum-meter", "phase", "event", "status-copy", "confidence", "evidence", "risk-level"].map((id) => [id, element(id)]));
const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;
const parameters = new URLSearchParams(location.search);
const preset = parameters.get("preset") === "arcade" ? "arcade" : "focus";
const previewPhase = parameters.get("phase");
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

document.body.dataset.preset = preset;
if (parameters.get("preview") === "light") document.body.dataset.preview = "light";

const palette = {
  observe: "#75dfff", act: "#a886ff", verify: "#62e3ad",
  wait: "#ffc568", recover: "#ff6486", complete: "#72e9bf"
};
const previewMode = previewPhase in palette;

if (previewMode) {
  document.body.dataset.previewState = "true";
  render({
    phase: previewPhase,
    status: previewPhase === "wait" ? "needs-attention" : "ready",
    momentum: 72,
    confidence: 84,
    riskLevel: previewPhase === "recover" ? "high" : "low",
    currentActivity: previewPhase === "wait" ? "Waiting for your approval" : "Codex activity preview"
  });
  elements.connection.textContent = "PREVIEW";
  expand(0);
}

function resize() {
  scale = devicePixelRatio || 1;
  canvas.width = innerWidth * scale;
  canvas.height = innerHeight * scale;
  context.setTransform(scale, 0, 0, scale, 0, 0);
}

function codingOrigin() {
  return { x: innerWidth * (.26 + Math.random() * .42), y: innerHeight * (.25 + Math.random() * .48) };
}

function expand(duration = 2100) {
  clearTimeout(collapseTimer);
  elements.hud.classList.remove("collapsed");
  if (duration > 0) collapseTimer = setTimeout(() => elements.hud.classList.add("collapsed"), duration);
}

function burst(color, amount, power = 1, mode = "radial", start = codingOrigin()) {
  if (reducedMotion) return;
  const count = Math.min(220, Math.round(amount * intensity));
  for (let index = 0; index < count; index += 1) {
    const angle = mode === "forward" ? -.55 + Math.random() * 1.1 : Math.random() * Math.PI * 2;
    const distance = mode === "inward" ? 75 + Math.random() * 150 : 0;
    const x = start.x + Math.cos(angle) * distance;
    const y = start.y + Math.sin(angle) * distance;
    const speed = (1.1 + Math.random() * 4.7) * power * intensity;
    particles.push({
      x, y,
      vx: mode === "inward" ? (start.x - x) / (30 + Math.random() * 12) : Math.cos(angle) * speed,
      vy: mode === "inward" ? (start.y - y) / (30 + Math.random() * 12) : Math.sin(angle) * speed,
      life: 34 + Math.random() * 44,
      maxLife: 78,
      size: .8 + Math.random() * (preset === "arcade" ? 3.2 : 2.1),
      color,
      drag: mode === "inward" ? 1.012 : .985,
      square: mode === "fragments"
    });
  }
}

function ring(color, power = 1, start = codingOrigin()) {
  if (!reducedMotion) rings.push({ ...start, radius: 8, life: 38, maxLife: 38, color, speed: 4.4 * power * intensity });
}

function scan(color) {
  if (!reducedMotion) scans.push({ x: innerWidth * .2, y: innerHeight * (.3 + Math.random() * .4), width: innerWidth * .5, life: 48, maxLife: 48, color });
}

function frame() {
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
    const head = item.x + item.width * progress;
    const gradient = context.createLinearGradient(head - 90, 0, head, 0);
    gradient.addColorStop(0, "transparent"); gradient.addColorStop(1, item.color);
    context.globalAlpha = Math.sin(progress * Math.PI) * .36;
    context.fillStyle = gradient;
    context.fillRect(head - 90, item.y, 90, 1.2);
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
  requestAnimationFrame(frame);
}

function statusCopy(next) {
  if (next.phase === "wait") return "Your approval is needed";
  if (next.phase === "recover") return "Confidence dropped; repairing the latest change";
  if (next.phase === "complete" && next.completion === "verified") return "Latest changes are backed by evidence";
  if (next.phase === "complete") return "Verification is still recommended";
  if (next.phase === "verify") return "Building confidence in the change";
  if (next.phase === "act") return "Applying a scoped change";
  return "Reading and understanding context";
}

function render(next = state) {
  state = { ...state, ...next };
  const phase = state.phase ?? "observe";
  const momentum = state.momentum ?? 0;
  document.body.dataset.phase = phase;
  document.body.dataset.status = state.status ?? "ready";
  elements.momentum.textContent = momentum;
  elements["momentum-meter"].style.setProperty("--progress", `${momentum * 3.6}deg`);
  elements.phase.textContent = phase.toUpperCase();
  elements.event.textContent = state.currentActivity ?? "Codex Power ready";
  elements["status-copy"].textContent = statusCopy(state);
  elements.confidence.textContent = `CONF ${state.confidence ?? 0}%`;
  elements.evidence.textContent = state.evidence?.length ? `${state.evidence.join("+").toUpperCase()} ✓` : "NO EVIDENCE";
  elements["risk-level"].textContent = `${String(state.riskLevel ?? "low").toUpperCase()} RISK`;
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
  const color = palette[phase];
  const start = codingOrigin();
  const momentumPower = .7 + Math.min(100, event.state?.momentum ?? 0) / 125;
  expand(phase === "wait" || phase === "recover" ? 0 : phase === "complete" ? 3200 : 2100);
  flashAt(start);

  if (event.type === "activity-start" && phase === "observe") {
    scan(color);
    if (preset === "arcade") setTimeout(() => scan(color), 130);
  } else if (event.type === "activity-start" && phase === "verify") {
    burst(color, 34, .55, "inward", start); ring(color, .55, start);
  } else if (event.type === "activity-start") {
    burst(color, 16, .55, "forward", start);
  } else if (event.type === "permission-request") {
    ring(color, .65, start); setTimeout(() => ring(color, .65, start), 320);
  } else if (event.type === "edit") {
    burst(color, 32, momentumPower, "forward", start); ring(color, momentumPower, start);
  } else if (event.type === "verification" && event.success) {
    burst(color, 62, momentumPower, "inward", start); ring(color, 1.25, start);
    setTimeout(() => burst(color, 38, .85, "radial", start), 280);
  } else if (event.type === "verification") {
    burst(color, 52, 1.05, "fragments", start); ring(color, .8, start);
  } else if (event.state?.completion === "verified") {
    ring(color, 1.55, start); burst(color, 95, 1.2, "radial", start);
    setTimeout(() => { ring("#a886ff", 1.2, start); burst("#a886ff", 52, .9, "radial", start); }, 180);
  }
}

if (!previewMode) {
  const stream = new EventSource("/api/stream");
  stream.onopen = () => { elements.connection.textContent = preset.toUpperCase(); };
  stream.onerror = () => { elements.connection.textContent = "RECONNECT"; };
  stream.onmessage = ({ data }) => {
    const event = JSON.parse(data);
    if (event.type === "connected") render(event.state);
    else react(event);
  };
}

addEventListener("resize", resize);
resize(); frame();
