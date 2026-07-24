import { nativeConfigFromEnvironment } from "./config.mjs";

export const interactionChecks = Object.freeze([
  ["cursor-spark", "Spark follows the real Codex insertion point"],
  ["cursor-neon", "Neon follows the real Codex insertion point"],
  ["cursor-orbit", "Orbit follows the real Codex insertion point"],
  ["cursor-ripple", "Ripple follows the real Codex insertion point"],
  ["cursor-prism", "Prism follows the real Codex insertion point"],
  ["cursor-wormhole", "Liquid wormhole follows the real Codex insertion point"],
  ["cursor-glitch", "Glitch slices follow the real Codex insertion point"],
  ["cursor-tentacle", "Soft tentacles follow the real Codex insertion point"],
  ["cursor-meme", "Chinese meme words follow the real Codex insertion point"],
  ["cursor-possum", "Hands-behind possum follows the real Codex insertion point"],
  ["cursor-fresh-cat", "Fresh cat follows the real Codex insertion point without covering input-method candidates"],
  ["cursor-knife-shield-dog", "Knife-shield dog waddles below the real Codex insertion point without added weapon graphics"],
  ["cursor-elegant-person", "Elegant person bows below the real Codex insertion point without covering input-method candidates"],
  ["prompt-injection", "A real UserPromptSubmit injects Typing Combo"],
  ["drag-restart", "Dragged position survives an HUD restart"],
  ["display-change", "Display attach/detach keeps the HUD visible"],
  ["inactive-hide", "Codex-window mode hides the HUD outside Codex"],
  ["inactive-stay", "Always-on-screen mode stays screen-anchored across apps and Spaces"],
  ["orb-context-menu", "Right-clicking the visible HUD opens the settings menu"],
  ["idle-hide", "Settled Idle hides after the configured delay"],
  ["idle-orb", "Settled Idle retains the quiet orb"],
  ["language-en", "English labels are correct"],
  ["language-zh", "Chinese labels are correct"],
  ["language-auto", "Automatic language follows the system preference"],
  ["install-upgrade", "Install and upgrade preserve settings and single instances"],
  ["stop-uninstall", "Stop and uninstall leave no running instances"]
].map(([id, title]) => Object.freeze({ id, title })));

const checkIds = new Set(interactionChecks.map((check) => check.id));
const recordableStatuses = new Set(["passed", "failed", "unavailable"]);

function loopbackEndpoint(value) {
  const endpoint = new URL(String(value));
  if (endpoint.protocol !== "http:" || endpoint.hostname !== "127.0.0.1" || endpoint.pathname !== "/api/stream") {
    throw new Error("Interaction checkpoint requires the local Power Mode stream endpoint");
  }
  return endpoint.toString();
}

function normalizedBaseline(configuration) {
  return {
    ...nativeConfigFromEnvironment({}, configuration),
    endpoint: loopbackEndpoint(configuration?.endpoint)
  };
}

export function createInteractionSession(configuration, pluginVersion, now = new Date()) {
  const baselineConfiguration = normalizedBaseline(configuration);
  return {
    schemaVersion: 1,
    status: "active",
    startedAt: now.toISOString(),
    restoredAt: null,
    pluginVersion: String(pluginVersion || "unknown"),
    baselineConfiguration,
    results: Object.fromEntries(interactionChecks.map((check) => [check.id, "pending"]))
  };
}

export function recordInteractionResult(session, checkId, status) {
  if (session?.schemaVersion !== 1 || session.status !== "active") throw new Error("No active interaction acceptance session");
  if (!checkIds.has(checkId)) throw new Error(`Unknown interaction check: ${checkId}`);
  if (!recordableStatuses.has(status)) throw new Error("Result must be passed, failed, or unavailable");
  return { ...session, results: { ...session.results, [checkId]: status } };
}

export function restoreInteractionSession(session, now = new Date()) {
  if (session?.schemaVersion !== 1 || !session.baselineConfiguration) throw new Error("Invalid interaction acceptance checkpoint");
  const normalized = normalizedBaseline(session.baselineConfiguration);
  const keys = Object.keys(normalized);
  if (keys.length !== Object.keys(session.baselineConfiguration).length
      || keys.some((key) => normalized[key] !== session.baselineConfiguration[key])) {
    throw new Error("Interaction acceptance baseline was modified or is invalid");
  }
  return { ...session, status: "restored", restoredAt: now.toISOString() };
}

export function summarizeInteractionSession(session) {
  if (session?.schemaVersion !== 1) throw new Error("Invalid interaction acceptance checkpoint");
  const checks = interactionChecks.map((check) => ({ ...check, status: session.results?.[check.id] ?? "pending" }));
  const counts = { pending: 0, passed: 0, failed: 0, unavailable: 0 };
  for (const check of checks) counts[check.status] = (counts[check.status] ?? 0) + 1;
  return { status: session.status, pluginVersion: session.pluginVersion, counts, checks };
}
