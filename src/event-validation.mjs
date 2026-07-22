const EVENT_TYPES = new Set([
  "connected", "activity-start", "permission-request", "edit", "edit-failure", "verification", "turn-stop"
]);
const PHASES = new Set(["observe", "act", "verify", "wait", "recover", "complete", "idle"]);
const SENSITIVE_KEYS = ["prompt", "command", "code", "patch", "tool_input", "tool_response"];

function boundedString(value, maximum = 256) {
  return typeof value === "string" && value.length > 0 && value.length <= maximum;
}

export function validateIncomingEvent(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return "Event must be a JSON object";
  if (!EVENT_TYPES.has(value.type)) return "Unsupported event type";
  if (!boundedString(value.sessionId, 256)) return "Invalid sessionId";
  if (!boundedString(value.timestamp, 64) || !Number.isFinite(Date.parse(value.timestamp))) return "Invalid timestamp";
  if (value.id !== undefined && !boundedString(value.id, 256)) return "Invalid event id";
  if (value.phase !== undefined && !PHASES.has(value.phase)) return "Invalid phase";
  if (value.preview === true && value.sessionId !== "demo") return "Preview events must use the demo session";
  if (value.preview !== true && value.sessionId === "demo") return "Demo events must be previews";
  if (value.state !== undefined && (!value.state || typeof value.state !== "object" || Array.isArray(value.state))) {
    return "Invalid event state";
  }
  for (const key of SENSITIVE_KEYS) {
    if (Object.hasOwn(value, key)) return `Sensitive field is not accepted: ${key}`;
  }
  for (const key of ["addedLines", "removedLines", "addedChars", "removedChars"]) {
    if (value[key] !== undefined && (!Number.isInteger(value[key]) || value[key] < 0 || value[key] > 1_000_000)) {
      return `Invalid ${key}`;
    }
  }
  if (value.success !== undefined && typeof value.success !== "boolean") return "Invalid verification result";
  return null;
}
