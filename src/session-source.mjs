import { open } from "node:fs/promises";

const HEADER_BYTES = 16 * 1024;

export function classifySessionSource(header = "") {
  const source = String(header).match(/"source"\s*:\s*"([^"]+)"/)?.[1]?.toLowerCase();
  const originator = String(header).match(/"originator"\s*:\s*"([^"]+)"/)?.[1]?.toLowerCase() ?? "";
  if (source === "vscode" || originator === "codex_work_desktop") return "desktop";
  if (source === "exec") return "cli";
  if (/"source"\s*:\s*\{[^}]*"subagent"/.test(String(header))) return "subagent";
  return "unknown";
}

export async function sessionSourceFromTranscript(transcriptPath) {
  if (!transcriptPath || typeof transcriptPath !== "string") return "unknown";
  let handle;
  try {
    handle = await open(transcriptPath, "r");
    const buffer = Buffer.alloc(HEADER_BYTES);
    const { bytesRead } = await handle.read(buffer, 0, buffer.length, 0);
    return classifySessionSource(buffer.subarray(0, bytesRead).toString("utf8"));
  } catch {
    return "unknown";
  } finally {
    await handle?.close().catch(() => {});
  }
}

export function shouldTrackSessionSource(sessionSource) {
  return sessionSource === "desktop";
}
