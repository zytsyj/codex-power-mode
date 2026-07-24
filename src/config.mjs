const NATIVE_EDGES = new Set(["smart", "top-right", "top-left", "bottom-right", "bottom-left", "center"]);
const IDLE_BEHAVIORS = new Set(["hide", "orb"]);
const LANGUAGES = new Set(["auto", "en", "zh-CN"]);
const ACTIVITY_SOURCES = new Set(["focused", "global", "mix"]);
const EFFECT_INTENSITIES = new Set(["low", "normal", "high"]);
const PRESETS = new Set(["focus", "arcade", "classic"]);
const CURSOR_EFFECTS = new Set(["off", "spark", "neon", "orbit", "ripple", "prism", "wormhole", "glitch", "tentacle", "meme", "possum", "freshcat", "knifeshield", "elegant"]);
const INACTIVE_BEHAVIORS = new Set(["hide", "stay"]);
const AUTO_HIDE_DELAYS = new Set([0, 2, 6]);
const ENERGY_GAIN_MULTIPLIERS = new Set([0.3, 0.4, 0.5, 0.6, 0.72, 0.85, 1, 1.15, 1.3, 1.5]);
const LEGACY_ENERGY_GAIN_MULTIPLIERS = new Map([[0.55, 0.5], [0.9, 0.85], [1.1, 1.15]]);

const hasValue = (environment, key) => Object.hasOwn(environment, key) && environment[key] !== undefined && environment[key] !== "";
const storedNumber = (value) => value === null || value === undefined || value === ""
  ? null
  : Number.isFinite(Number(value)) ? Number(value) : null;

export function servicePortFromEnvironment(environment = {}) {
  const parsedPort = Number(environment.CODEX_POWER_MODE_PORT);
  return Number.isInteger(parsedPort) && parsedPort >= 1 && parsedPort <= 65_535 ? parsedPort : 4_737;
}

export function serviceEndpointFromEnvironment(environment = {}) {
  return `http://127.0.0.1:${servicePortFromEnvironment(environment)}`;
}

export function nativeStreamEndpointFromEnvironment(environment = {}) {
  return `${serviceEndpointFromEnvironment(environment)}/api/stream`;
}

export function nativeConfigFromEnvironment(environment = {}, stored = {}) {
  const settings = stored.schemaVersion === 1 ? stored : {};
  const onboardingVersion = Number.isInteger(settings.onboardingVersion) && settings.onboardingVersion >= 0
    ? settings.onboardingVersion
    : null;
  const parsedScale = Number.parseFloat(hasValue(environment, "CODEX_POWER_MODE_SCALE") ? environment.CODEX_POWER_MODE_SCALE : settings.scale);
  const preset = hasValue(environment, "CODEX_POWER_MODE_PRESET") ? environment.CODEX_POWER_MODE_PRESET : settings.preset;
  const normalizedPreset = PRESETS.has(preset) ? preset : "focus";
  const edge = hasValue(environment, "CODEX_POWER_MODE_EDGE") ? environment.CODEX_POWER_MODE_EDGE : settings.edge;
  const requestedIdleBehavior = hasValue(environment, "CODEX_POWER_MODE_IDLE") ? environment.CODEX_POWER_MODE_IDLE : settings.idleBehavior;
  const idleBehavior = requestedIdleBehavior === "always" ? "orb" : requestedIdleBehavior;
  const language = hasValue(environment, "CODEX_POWER_MODE_LANGUAGE") ? environment.CODEX_POWER_MODE_LANGUAGE : settings.language;
  const activitySource = hasValue(environment, "CODEX_POWER_MODE_ACTIVITY_SOURCE")
    ? environment.CODEX_POWER_MODE_ACTIVITY_SOURCE
    : settings.activitySource;
  const effectIntensity = hasValue(environment, "CODEX_POWER_MODE_INTENSITY")
    ? environment.CODEX_POWER_MODE_INTENSITY
    : settings.effectIntensity;
  const requestedEnergyGainMultiplier = Number(hasValue(environment, "CODEX_POWER_MODE_ENERGY_GAIN")
    ? environment.CODEX_POWER_MODE_ENERGY_GAIN
    : settings.energyGainMultiplier);
  const reducedMotion = hasValue(environment, "CODEX_POWER_MODE_REDUCED_MOTION")
    ? environment.CODEX_POWER_MODE_REDUCED_MOTION === "1"
    : settings.reducedMotion === true;
  const storedInactiveBehavior = settings.inactiveBehavior === "follow"
    ? "stay"
    : INACTIVE_BEHAVIORS.has(settings.inactiveBehavior)
      ? settings.inactiveBehavior
    : settings.followWhenInactive === true ? "stay" : "hide";
  const requestedInactiveBehavior = hasValue(environment, "CODEX_POWER_MODE_INACTIVE_BEHAVIOR")
    ? environment.CODEX_POWER_MODE_INACTIVE_BEHAVIOR
    : storedInactiveBehavior;
  const inactiveBehavior = requestedInactiveBehavior === "follow" ? "stay" : requestedInactiveBehavior;
  const requestedAutoHideDelay = Number(hasValue(environment, "CODEX_POWER_MODE_AUTO_HIDE_DELAY")
    ? environment.CODEX_POWER_MODE_AUTO_HIDE_DELAY
    : settings.autoHideDelay);
  const enabled = hasValue(environment, "CODEX_POWER_MODE_ENABLED")
    ? environment.CODEX_POWER_MODE_ENABLED !== "0"
    : settings.enabled !== false;
  const showCombo = hasValue(environment, "CODEX_POWER_MODE_SHOW_COMBO")
    ? environment.CODEX_POWER_MODE_SHOW_COMBO !== "0"
    : settings.showCombo !== false;
  const typingCombo = normalizedPreset === "classic" || (hasValue(environment, "CODEX_POWER_MODE_TYPING_COMBO")
    ? environment.CODEX_POWER_MODE_TYPING_COMBO !== "0"
    : settings.typingCombo === true);
  const cursorEffect = hasValue(environment, "CODEX_POWER_MODE_CURSOR_EFFECT")
    ? environment.CODEX_POWER_MODE_CURSOR_EFFECT
    : settings.cursorEffect;
  return {
    schemaVersion: 1,
    preset: normalizedPreset,
    edge: NATIVE_EDGES.has(edge) ? edge : "smart",
    scale: Number.isFinite(parsedScale) ? Math.min(1.6, Math.max(0.75, parsedScale)) : 1.15,
    reducedMotion,
    inactiveBehavior: INACTIVE_BEHAVIORS.has(inactiveBehavior) ? inactiveBehavior : "hide",
    autoHideDelay: AUTO_HIDE_DELAYS.has(requestedAutoHideDelay) ? requestedAutoHideDelay : 2,
    enabled,
    idleBehavior: IDLE_BEHAVIORS.has(idleBehavior) ? idleBehavior : "hide",
    language: LANGUAGES.has(language) ? language : "auto",
    activitySource: ACTIVITY_SOURCES.has(activitySource) ? activitySource : "focused",
    effectIntensity: EFFECT_INTENSITIES.has(effectIntensity) ? effectIntensity : "normal",
    energyGainMultiplier: ENERGY_GAIN_MULTIPLIERS.has(requestedEnergyGainMultiplier)
      ? requestedEnergyGainMultiplier
      : LEGACY_ENERGY_GAIN_MULTIPLIERS.get(requestedEnergyGainMultiplier) ?? 0.72,
    showCombo,
    typingCombo,
    cursorEffect: CURSOR_EFFECTS.has(cursorEffect) ? cursorEffect : "spark",
    positionX: storedNumber(settings.positionX),
    positionY: storedNumber(settings.positionY),
    ...(onboardingVersion === null ? {} : { onboardingVersion })
  };
}
