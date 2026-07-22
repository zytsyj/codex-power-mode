import assert from "node:assert/strict";
import test from "node:test";
import { isNativeOverlayCommand } from "../src/native-process.mjs";

test("native PID validation only accepts the expected overlay binary", () => {
  const binary = "/Users/example/Power Mode/codex-power-mode-overlay";
  assert.equal(isNativeOverlayCommand(binary, binary), true);
  assert.equal(isNativeOverlayCommand(`${binary} --future-option`, binary), true);
  assert.equal(isNativeOverlayCommand("/tmp/codex-power-mode-overlay", binary), false);
  assert.equal(isNativeOverlayCommand("node unrelated.mjs", binary), false);
  assert.equal(isNativeOverlayCommand("", binary), false);
});
