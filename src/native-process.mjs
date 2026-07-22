import path from "node:path";

export function isNativeOverlayCommand(command, expectedBinary) {
  if (typeof command !== "string" || typeof expectedBinary !== "string") return false;
  const actual = command.trim();
  const expected = path.resolve(expectedBinary);
  return actual === expected || actual.startsWith(`${expected} `);
}
