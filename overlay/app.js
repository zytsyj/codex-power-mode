const canvas = document.querySelector("#effects");
const context = canvas.getContext("2d");
const byId = (id) => document.querySelector(`#${id}`);
const elements = Object.fromEntries([
  "connection", "momentum", "momentum-meter", "phase", "event", "status-copy", "confidence",
  "confidence-bar", "confidence-copy", "evidence", "evidence-count", "risk-level", "risk-copy",
  "steps", "lines", "checks", "best"
].map((id) => [id, byId(id)]));
const particles = [];
const rings = [];
let state = {};
let scale = window.devicePixelRatio || 1;

const palette = {
  observe: "#8d7cff", act: "#a17cff", verify: "#64e9a5",
  wait: "#ffc76d", recover: "#ff6488", complete: "#71e6c0"
};

function resize() {
  scale = window.devicePixelRatio || 1;
  canvas.width = innerWidth * scale;
  canvas.height = innerHeight * scale;
  context.setTransform(scale, 0, 0, scale, 0, 0);
}

function origin() {
  return {
    x: innerWidth * (.28 + Math.random() * .38),
    y: innerHeight * (.25 + Math.random() * .46)
  };
}

function burst(color, amount = 32, power = 1, directional = false) {
  const start = origin();
  for (let index = 0; index < Math.min(amount, 150); index += 1) {
    const angle = directional ? (-.65 + Math.random() * 1.3) : Math.random() * Math.PI * 2;
    const speed = (1 + Math.random() * 4.8) * power;
    particles.push({
      x: start.x, y: start.y,
      vx: Math.cos(angle) * speed, vy: Math.sin(angle) * speed,
      life: 38 + Math.random() * 48, maxLife: 86,
      size: 1 + Math.random() * 2.7, color
    });
  }
}

function ring(color, power = 1) {
  const start = origin();
  rings.push({ ...start, radius: 120, life: 42, maxLife: 42, color, speed: 4 * power });
}

function frame() {
  context.clearRect(0, 0, innerWidth, innerHeight);
  context.globalCompositeOperation = "lighter";
  for (let index = rings.length - 1; index >= 0; index -= 1) {
    const item = rings[index];
    item.radius += item.speed;
    item.life -= 1;
    if (item.life <= 0) { rings.splice(index, 1); continue; }
    context.globalAlpha = item.life / item.maxLife * .34;
    context.strokeStyle = item.color;
    context.lineWidth = 1.2;
    context.beginPath();
    context.arc(item.x, item.y, item.radius, 0, Math.PI * 2);
    context.stroke();
  }
  for (let index = particles.length - 1; index >= 0; index -= 1) {
    const item = particles[index];
    item.x += item.vx; item.y += item.vy;
    item.vx *= .986; item.vy *= .986; item.life -= 1;
    if (item.life <= 0) { particles.splice(index, 1); continue; }
    context.globalAlpha = Math.min(.85, item.life / 22);
    context.fillStyle = item.color;
    context.beginPath(); context.arc(item.x, item.y, item.size, 0, Math.PI * 2); context.fill();
  }
  context.globalAlpha = 1;
  requestAnimationFrame(frame);
}

function statusCopy(next) {
  if (next.phase === "wait") return "Codex is paused until you respond";
  if (next.phase === "recover") return "A check failed; confidence is intentionally reduced";
  if (next.phase === "complete" && next.completion === "verified") return "Evidence-backed completion";
  if (next.phase === "complete" && next.completion === "unverified") return "Finished, but the latest changes remain unverified";
  if (next.phase === "verify") return "Building evidence for the current changes";
  if (next.phase === "act") return "Making a scoped change";
  return "Understanding the task and its context";
}

function confidenceCopy(value) {
  if (value >= 75) return "Strong verification evidence for this turn.";
  if (value >= 35) return "Some evidence collected; more checks may help.";
  return "Run checks to build verified confidence.";
}

function renderEvidence(evidence = []) {
  elements["evidence-count"].textContent = evidence.length;
  elements.evidence.replaceChildren();
  if (!evidence.length) {
    const empty = document.createElement("span");
    empty.className = "empty";
    empty.textContent = "No checks recorded";
    elements.evidence.append(empty);
    return;
  }
  for (const item of evidence) {
    const chip = document.createElement("span");
    chip.textContent = `✓ ${item}`;
    elements.evidence.append(chip);
  }
}

function renderRisk(next) {
  const value = next.risk ?? 0;
  const level = next.riskLevel ?? "low";
  const colors = { low: "#64e9a5", medium: "#ffc76d", high: "#ff6488" };
  const count = Math.max(1, Math.ceil(value / 20));
  document.documentElement.style.setProperty("--risk-color", colors[level]);
  elements["risk-level"].textContent = level.toUpperCase();
  elements["risk-copy"].textContent = level === "high" ? "Large or unverified change surface." : level === "medium" ? "Verification would lower current risk." : "Scope is controlled.";
  document.querySelectorAll(".risk-dots i").forEach((dot, index) => dot.classList.toggle("on", index < count));
}

function render(next = state) {
  state = { ...state, ...next };
  const phase = state.phase ?? "observe";
  const momentum = state.momentum ?? 0;
  const confidence = state.confidence ?? 0;
  document.body.dataset.phase = phase;
  document.body.dataset.status = state.status ?? "ready";
  elements.momentum.textContent = momentum;
  elements["momentum-meter"].style.setProperty("--progress", `${momentum * 3.6}deg`);
  elements.phase.textContent = phase.toUpperCase();
  elements.event.textContent = state.currentActivity ?? "Waiting for Codex activity";
  elements["status-copy"].textContent = statusCopy(state);
  elements.confidence.textContent = `${confidence}%`;
  elements["confidence-bar"].style.width = `${confidence}%`;
  elements["confidence-copy"].textContent = confidenceCopy(confidence);
  elements.steps.textContent = state.steps ?? 0;
  elements.lines.textContent = `+${state.addedLines ?? 0} / −${state.removedLines ?? 0}`;
  elements.checks.textContent = `${state.passedVerifications ?? 0} / ${state.verifications ?? 0}`;
  elements.best.textContent = state.bestMomentum ?? 0;
  document.querySelectorAll("[data-step]").forEach((item) => item.classList.toggle("active", item.dataset.step === phase));
  renderEvidence(state.evidence);
  renderRisk(state);
}

function describe(event) {
  if (event.type === "activity-start") return event.phase === "verify" ? `Running ${event.category || "verification"}` : event.phase === "observe" ? "Reading context" : "Starting a tool";
  if (event.type === "permission-request") return "Waiting for your approval";
  if (event.type === "edit") return `Changed ${event.addedLines + event.removedLines} lines`;
  if (event.type === "verification") return `${event.category} ${event.success ? "passed" : "failed"}`;
  if (event.type === "turn-stop") return event.state?.completion === "verified" ? "Completed with evidence" : "Turn complete";
  return event.state?.currentActivity || "Power Mode online";
}

function react(event) {
  render(event.state);
  elements.event.textContent = describe(event);
  document.body.classList.remove("flash");
  void document.body.offsetWidth;
  document.body.classList.add("flash");
  const phase = event.state?.phase ?? "observe";
  const color = palette[phase];

  if (event.type === "activity-start") {
    ring(color, .55);
    if (phase !== "observe") burst(color, 14, .55, true);
  } else if (event.type === "permission-request") {
    ring(color, .75);
    setTimeout(() => ring(color, .75), 300);
  } else if (event.type === "edit") {
    burst(color, Math.max(24, Math.min(90, (event.addedLines + event.removedLines) * 2)), .9, true);
    ring(color, .8);
  } else if (event.type === "verification") {
    burst(color, event.success ? 75 : 48, event.success ? 1.1 : .75);
    ring(color, event.success ? 1.15 : .85);
  } else if (event.state?.completion === "verified") {
    ring(color, 1.35); burst("#71e6c0", 110, 1.25);
    setTimeout(() => burst("#8d7cff", 65, .9), 180);
  }
}

const stream = new EventSource("/api/stream");
stream.onopen = () => { elements.connection.textContent = "LIVE"; elements.connection.parentElement.classList.add("online"); };
stream.onerror = () => { elements.connection.textContent = "RECONNECTING"; elements.connection.parentElement.classList.remove("online"); };
stream.onmessage = ({ data }) => {
  const event = JSON.parse(data);
  if (event.type === "connected") render(event.state);
  else react(event);
};

addEventListener("resize", resize);
resize(); frame();
