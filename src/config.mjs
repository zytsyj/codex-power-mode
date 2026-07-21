const NATIVE_EDGES = new Set(["top-right", "top-left", "bottom-right", "bottom-left", "center"]);

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

export function nativeStreamEndpointFromConfiguration(configuration = {}) {
  return configuration.endpoint || "http://127.0.0.1:4737/api/stream";
}

export function nativeConfigFromEnvironment(environment = {}) {
  const parsedScale = Number.parseFloat(environment.CODEX_POWER_MODE_SCALE);
  return {
    preset: environment.CODEX_POWER_MODE_PRESET === "arcade" ? "arcade" : "focus",
    edge: NATIVE_EDGES.has(environment.CODEX_POWER_MODE_EDGE) ? environment.CODEX_POWER_MODE_EDGE : "top-right",
    scale: Number.isFinite(parsedScale) ? Math.min(1.6, Math.max(0.75, parsedScale)) : 1.15,
    reducedMotion: environment.CODEX_POWER_MODE_REDUCED_MOTION === "1",
    followWhenInactive: environment.CODEX_POWER_MODE_FOLLOW_WHEN_INACTIVE === "1"
  };
}
