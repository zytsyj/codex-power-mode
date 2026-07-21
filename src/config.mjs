const NATIVE_EDGES = new Set(["smart", "top-right", "top-left", "bottom-right", "bottom-left", "center"]);
const IDLE_BEHAVIORS = new Set(["hide", "orb", "always"]);
const LANGUAGES = new Set(["auto", "en", "zh-CN"]);
const ACTIVITY_SOURCES = new Set(["focused", "global"]);

const hasValue = (environment, key) => Object.hasOwn(environment, key) && environment[key] !== undefined && environment[key] !== "";
const storedNumber = (value) => Number.isFinite(Number(value)) ? Number(value) : null;

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
  const parsedScale = Number.parseFloat(hasValue(environment, "CODEX_POWER_MODE_SCALE") ? environment.CODEX_POWER_MODE_SCALE : settings.scale);
  const preset = hasValue(environment, "CODEX_POWER_MODE_PRESET") ? environment.CODEX_POWER_MODE_PRESET : settings.preset;
  const edge = hasValue(environment, "CODEX_POWER_MODE_EDGE") ? environment.CODEX_POWER_MODE_EDGE : settings.edge;
  const idleBehavior = hasValue(environment, "CODEX_POWER_MODE_IDLE") ? environment.CODEX_POWER_MODE_IDLE : settings.idleBehavior;
  const language = hasValue(environment, "CODEX_POWER_MODE_LANGUAGE") ? environment.CODEX_POWER_MODE_LANGUAGE : settings.language;
  const activitySource = hasValue(environment, "CODEX_POWER_MODE_ACTIVITY_SOURCE")
    ? environment.CODEX_POWER_MODE_ACTIVITY_SOURCE
    : settings.activitySource;
  const reducedMotion = hasValue(environment, "CODEX_POWER_MODE_REDUCED_MOTION")
    ? environment.CODEX_POWER_MODE_REDUCED_MOTION === "1"
    : settings.reducedMotion === true;
  const followWhenInactive = hasValue(environment, "CODEX_POWER_MODE_FOLLOW_WHEN_INACTIVE")
    ? environment.CODEX_POWER_MODE_FOLLOW_WHEN_INACTIVE === "1"
    : settings.followWhenInactive === true;
  const enabled = hasValue(environment, "CODEX_POWER_MODE_ENABLED")
    ? environment.CODEX_POWER_MODE_ENABLED !== "0"
    : settings.enabled !== false;
  return {
    schemaVersion: 1,
    preset: preset === "arcade" ? "arcade" : "focus",
    edge: NATIVE_EDGES.has(edge) ? edge : "smart",
    scale: Number.isFinite(parsedScale) ? Math.min(1.6, Math.max(0.75, parsedScale)) : 1.15,
    reducedMotion,
    followWhenInactive,
    enabled,
    idleBehavior: IDLE_BEHAVIORS.has(idleBehavior) ? idleBehavior : "hide",
    language: LANGUAGES.has(language) ? language : "auto",
    activitySource: ACTIVITY_SOURCES.has(activitySource) ? activitySource : "focused",
    positionX: storedNumber(settings.positionX),
    positionY: storedNumber(settings.positionY)
  };
}
