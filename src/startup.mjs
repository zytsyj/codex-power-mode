export function startupMode(platform = process.platform, environment = process.env) {
  const autoNative = environment.CODEX_POWER_MODE_AUTO_NATIVE !== "0";
  return platform === "darwin" && autoNative ? "native" : "start";
}
