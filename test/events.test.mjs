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
    turn_id: "turn-1",
    cwd: "/tmp/project"
  }, 1_000);
  assert.equal(event.type, "edit");
  assert.equal(event.addedLines, 1);
  assert.equal(event.removedLines, 1);
  assert.equal(event.sessionId, "session-1");
});
