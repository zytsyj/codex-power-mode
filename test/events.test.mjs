import test from "node:test";
import assert from "node:assert/strict";
import { classifyCommand, eventFromHook, parsePatch } from "../src/events.mjs";

test("parsePatch counts added and removed source lines", () => {
  assert.deepEqual(parsePatch("*** Begin Patch\n-old\n+new value\n+next\n*** End Patch"), {
    addedLines: 2,
    removedLines: 1,
    addedChars: 13,
    removedChars: 3
  });
});

test("classifyCommand recognizes successful tests", () => {
  assert.deepEqual(classifyCommand("npm test", { exit_code: 0 }), {
    type: "verification",
    category: "test",
    success: true
  });
});

test("classifyCommand recognizes the Node test runner", () => {
  assert.deepEqual(classifyCommand("node --test", { exit_code: 0 }), {
    type: "verification",
    category: "test",
    success: true
  });
});

test("classifyCommand recognizes a failed build", () => {
  assert.deepEqual(classifyCommand("pnpm run build", { exitCode: 1 }), {
    type: "verification",
    category: "build",
    success: false
  });
});

test("eventFromHook converts apply_patch input into an edit event", () => {
  const event = eventFromHook({
    hook_event_name: "PostToolUse",
    tool_name: "apply_patch",
    tool_input: { command: "+hello\n-world" },
    session_id: "session-1",
    session_source: "desktop",
    turn_id: "turn-1",
    cwd: "/tmp/project"
  }, 1_000);
  assert.equal(event.type, "edit");
  assert.equal(event.addedLines, 1);
  assert.equal(event.removedLines, 1);
  assert.equal(event.sessionId, "session-1");
  assert.equal(event.sessionSource, "desktop");
});

test("eventFromHook accepts Codex freeform apply_patch input", () => {
  const event = eventFromHook({
    hook_event_name: "PostToolUse",
    tool_name: "apply_patch",
    tool_input: "*** Begin Patch\n*** Update File: demo.js\n-old\n+new value\n+next\n*** End Patch"
  }, 1_000);
  assert.equal(event.type, "edit");
  assert.equal(event.addedLines, 2);
  assert.equal(event.removedLines, 1);
  assert.equal(event.addedChars, 13);
  assert.equal(event.removedChars, 3);
});

test("eventFromHook accepts object patch input aliases", () => {
  const event = eventFromHook({
    hook_event_name: "PostToolUse",
    tool_name: "apply_patch",
    tool_input: { patch: "+hello\n-world" }
  }, 1_000);
  assert.equal(event.type, "edit");
  assert.equal(event.addedLines, 1);
  assert.equal(event.removedLines, 1);
});

test("eventFromHook reports a failed patch without counting an edit", () => {
  const event = eventFromHook({
    hook_event_name: "PostToolUse",
    tool_name: "apply_patch",
    tool_input: "+new value\n-old value",
    tool_response: { success: false }
  }, 1_000);
  assert.equal(event.type, "edit-failure");
  assert.equal("addedLines" in event, false);
  assert.equal("removedLines" in event, false);
});

test("eventFromHook maps read tools to observe activity", () => {
  const event = eventFromHook({ hook_event_name: "PreToolUse", tool_name: "Grep" }, 1_000);
  assert.equal(event.type, "activity-start");
  assert.equal(event.phase, "observe");
  assert.equal(event.toolGroup, "search");
});

test("eventFromHook recognizes verification before execution", () => {
  const event = eventFromHook({
    hook_event_name: "PreToolUse",
    tool_name: "Bash",
    tool_input: { command: "npm test" }
  }, 1_000);
  assert.equal(event.type, "activity-start");
  assert.equal(event.phase, "verify");
  assert.equal(event.category, "test");
});

test("eventFromHook maps Codex exec_command cmd input through verification lifecycle", () => {
  const before = eventFromHook({
    hook_event_name: "PreToolUse",
    tool_name: "exec_command",
    tool_input: { cmd: "npm run check" }
  }, 1_000);
  assert.equal(before.type, "activity-start");
  assert.equal(before.phase, "verify");
  assert.equal(before.category, "lint");
  assert.equal(before.toolGroup, "command");

  const after = eventFromHook({
    hook_event_name: "PostToolUse",
    tool_name: "exec_command",
    tool_input: { cmd: "npm run check" },
    tool_response: { exit_code: 0 }
  }, 2_000);
  assert.deepEqual({ type: after.type, category: after.category, success: after.success }, {
    type: "verification", category: "lint", success: true
  });
});

test("eventFromHook exposes permission waits without command content", () => {
  const event = eventFromHook({ hook_event_name: "PermissionRequest", tool_name: "Bash" }, 1_000);
  assert.equal(event.type, "permission-request");
  assert.equal(event.toolGroup, "command");
  assert.equal("command" in event, false);
});
