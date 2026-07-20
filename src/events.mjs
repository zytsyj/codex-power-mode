const TEST_PATTERN = /(?:^|\s)(?:npm|pnpm|yarn|bun)\s+(?:run\s+)?test\b|\b(?:pytest|vitest|jest|go test|cargo test|swift test|dotnet test|mvn test|gradle test)\b/i;
const BUILD_PATTERN = /(?:^|\s)(?:npm|pnpm|yarn|bun)\s+(?:run\s+)?build\b|\b(?:cargo build|go build|swift build|dotnet build|mvn package|gradle build)\b/i;
const LINT_PATTERN = /(?:^|\s)(?:npm|pnpm|yarn|bun)\s+(?:run\s+)?(?:lint|typecheck|check)\b|\b(?:eslint|ruff|mypy|tsc|biome check)\b/i;
const OBSERVE_TOOLS = /^(?:Read|Glob|Grep|WebSearch|WebFetch|ListMcpResources|ReadMcpResource)$/i;
const EDIT_TOOLS = /^(?:apply_patch|Edit|Write)$/i;
const COMMAND_TOOLS = /^(?:Bash|exec_command)$/i;

export function parsePatch(command = "") {
  const lines = String(command).split(/\r?\n/);
  let addedLines = 0;
  let removedLines = 0;
  let addedChars = 0;
  let removedChars = 0;

  for (const line of lines) {
    if (line.startsWith("+++") || line.startsWith("---")) continue;
    if (line.startsWith("+")) {
      addedLines += 1;
      addedChars += Math.max(0, line.length - 1);
    } else if (line.startsWith("-")) {
      removedLines += 1;
      removedChars += Math.max(0, line.length - 1);
    }
  }

  return { addedLines, removedLines, addedChars, removedChars };
}

function responseText(response) {
  if (typeof response === "string") return response;
  try { return JSON.stringify(response ?? {}); } catch { return String(response ?? ""); }
}

export function didCommandSucceed(response) {
  if (response && typeof response === "object") {
    for (const key of ["exit_code", "exitCode", "status"]) {
      if (typeof response[key] === "number") return response[key] === 0;
    }
    if (typeof response.success === "boolean") return response.success;
  }
  const text = responseText(response);
  if (/"(?:exit_code|exitCode|status)"\s*:\s*[1-9]\d*/.test(text)) return false;
  if (/"success"\s*:\s*false/.test(text)) return false;
  if (/\b(?:command failed|tests? failed|build failed)\b/i.test(text)) return false;
  return true;
}

export function classifyCommand(command = "", response = {}) {
  const value = String(command);
  const success = didCommandSucceed(response);
  if (TEST_PATTERN.test(value)) return { type: "verification", category: "test", success };
  if (BUILD_PATTERN.test(value)) return { type: "verification", category: "build", success };
  if (LINT_PATTERN.test(value)) return { type: "verification", category: "lint", success };
  return null;
}

function commandCategory(command = "") {
  const classified = classifyCommand(command, {});
  return classified?.category ?? null;
}

function toolText(toolInput) {
  if (typeof toolInput === "string") return toolInput;
  return toolInput?.command ?? toolInput?.cmd ?? toolInput?.patch ?? "";
}

export function eventFromHook(input, now = Date.now()) {
  const base = {
    id: `${now}-${Math.random().toString(36).slice(2, 9)}`,
    timestamp: new Date(now).toISOString(),
    sessionId: input.session_id ?? "unknown",
    turnId: input.turn_id ?? null,
    cwd: input.cwd ?? process.cwd()
  };
  const toolName = input.tool_name ?? "";
  const command = toolText(input.tool_input);

  if (input.hook_event_name === "Stop") return { ...base, type: "turn-stop" };
  if (input.hook_event_name === "PermissionRequest") {
    return { ...base, type: "permission-request", toolGroup: EDIT_TOOLS.test(toolName) ? "change" : "command" };
  }
  if (input.hook_event_name === "PreToolUse") {
    const category = COMMAND_TOOLS.test(toolName) ? commandCategory(command) : null;
    const phase = category ? "verify" : OBSERVE_TOOLS.test(toolName) ? "observe" : "act";
    const toolGroup = OBSERVE_TOOLS.test(toolName) ? "search" : COMMAND_TOOLS.test(toolName) ? "command" : EDIT_TOOLS.test(toolName) ? "change" : "tool";
    return { ...base, type: "activity-start", phase, category, toolGroup };
  }
  if (input.hook_event_name !== "PostToolUse") return null;

  if (EDIT_TOOLS.test(toolName)) {
    if (!didCommandSucceed(input.tool_response)) return { ...base, type: "edit-failure" };
    const delta = parsePatch(command);
    if (!delta.addedLines && !delta.removedLines) return null;
    return { ...base, type: "edit", ...delta };
  }
  if (COMMAND_TOOLS.test(toolName)) {
    const classified = classifyCommand(command, input.tool_response);
    return classified ? { ...base, ...classified } : null;
  }
  return null;
}
