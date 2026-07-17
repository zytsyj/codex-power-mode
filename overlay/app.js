const canvas = document.querySelector("#effects");
const context = canvas.getContext("2d");
const elements = Object.fromEntries(["connection", "mode", "combo", "event", "score", "best", "lines", "checks"].map((id) => [id, document.querySelector(`#${id}`)]));
const particles = [];
let state = {};
let scale = window.devicePixelRatio || 1;

function resize() {
  scale = window.devicePixelRatio || 1;
  canvas.width = innerWidth * scale;
  canvas.height = innerHeight * scale;
  context.setTransform(scale, 0, 0, scale, 0, 0);
}

function burst(color, amount = 50, power = 1) {
  const originX = innerWidth * (.42 + Math.random() * .16);
  const originY = innerHeight * .52;
  for (let index = 0; index < Math.min(amount, 180); index += 1) {
    const angle = Math.random() * Math.PI * 2;
    const speed = (1.5 + Math.random() * 6) * power;
    particles.push({
      x: originX,
      y: originY,
      vx: Math.cos(angle) * speed,
      vy: Math.sin(angle) * speed - 1.5,
      life: 45 + Math.random() * 55,
      maxLife: 100,
      size: 1.5 + Math.random() * 4,
      color
    });
  }
}

function frame() {
  context.clearRect(0, 0, innerWidth, innerHeight);
  context.globalCompositeOperation = "lighter";
  for (let index = particles.length - 1; index >= 0; index -= 1) {
    const particle = particles[index];
    particle.x += particle.vx;
    particle.y += particle.vy;
    particle.vy += .065;
    particle.vx *= .992;
    particle.life -= 1;
    if (particle.life <= 0) {
      particles.splice(index, 1);
      continue;
    }
    context.globalAlpha = Math.min(1, particle.life / 24);
    context.fillStyle = particle.color;
    context.beginPath();
    context.arc(particle.x, particle.y, particle.size, 0, Math.PI * 2);
    context.fill();
  }
  context.globalAlpha = 1;
  requestAnimationFrame(frame);
}

function render(next = state) {
  state = { ...state, ...next };
  elements.combo.textContent = state.combo ?? 0;
  elements.score.textContent = state.score ?? 0;
  elements.best.textContent = state.bestCombo ?? 0;
  elements.lines.textContent = `+${state.addedLines ?? 0} / −${state.removedLines ?? 0}`;
  elements.checks.textContent = state.verifications ?? 0;
  elements.mode.textContent = String(state.mode ?? "idle").toUpperCase();
  document.body.className = state.mode === "danger" ? "danger" : state.mode === "victory" ? "victory" : "";
}

function describe(event) {
  if (event.type === "edit") return `CODE SURGE  +${event.addedLines}  −${event.removedLines}`;
  if (event.type === "verification") return `${event.category.toUpperCase()} ${event.success ? "PASSED" : "FAILED"}`;
  if (event.type === "turn-stop") return event.state?.mode === "victory" ? "MISSION COMPLETE" : "AWAITING VERIFICATION";
  return "POWER MODE ONLINE";
}

function react(event) {
  render(event.state);
  elements.event.textContent = describe(event);
  document.body.classList.remove("flash");
  void document.body.offsetWidth;
  document.body.classList.add("flash");

  if (event.type === "edit") {
    const amount = Math.max(18, event.addedLines * 5 + event.removedLines * 3);
    burst(event.removedLines > event.addedLines ? "#ff4d7d" : "#8b6cff", amount, 1);
    if (event.addedLines) burst("#4de8ff", Math.min(80, event.addedLines * 3), .65);
  } else if (event.type === "verification") {
    burst(event.success ? "#56f39a" : "#ff315f", event.success ? 110 : 70, event.success ? 1.25 : .8);
  } else if (event.state?.mode === "victory") {
    burst("#56f39a", 180, 1.55);
    setTimeout(() => burst("#8b6cff", 180, 1.5), 180);
    setTimeout(() => burst("#4de8ff", 180, 1.45), 360);
  }
}

const stream = new EventSource("/api/stream");
stream.onopen = () => {
  elements.connection.textContent = "LIVE";
  elements.connection.classList.add("online");
};
stream.onerror = () => {
  elements.connection.textContent = "RECONNECTING";
  elements.connection.classList.remove("online");
};
stream.onmessage = ({ data }) => {
  const event = JSON.parse(data);
  if (event.type === "connected") render(event.state);
  else react(event);
};

addEventListener("resize", resize);
resize();
frame();
