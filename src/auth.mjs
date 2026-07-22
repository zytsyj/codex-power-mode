import { randomBytes, timingSafeEqual } from "node:crypto";
import { chmod, mkdir, open, readFile } from "node:fs/promises";
import path from "node:path";

const TOKEN_PATTERN = /^[a-f0-9]{64}$/;
const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

export function serviceTokenPath(dataDir) {
  return path.join(dataDir, "service-token");
}

export async function ensureServiceToken(dataDir) {
  const tokenFile = serviceTokenPath(dataDir);
  await mkdir(dataDir, { recursive: true });
  try {
    const existing = (await readFile(tokenFile, "utf8")).trim();
    if (!TOKEN_PATTERN.test(existing)) throw new Error("Invalid Power Mode service token");
    await chmod(tokenFile, 0o600);
    return existing;
  } catch (error) {
    if (error.code && error.code !== "ENOENT") throw error;
  }

  const token = randomBytes(32).toString("hex");
  try {
    const handle = await open(tokenFile, "wx", 0o600);
    try {
      await handle.writeFile(`${token}\n`, "utf8");
    } finally {
      await handle.close();
    }
    return token;
  } catch (error) {
    if (error.code !== "EEXIST") throw error;
    for (let attempt = 0; attempt < 20; attempt += 1) {
      const existing = (await readFile(tokenFile, "utf8")).trim();
      if (TOKEN_PATTERN.test(existing)) {
        await chmod(tokenFile, 0o600);
        return existing;
      }
      await wait(5);
    }
    throw new Error("Invalid Power Mode service token");
  }
}

export function bearerHeaders(token, headers = {}) {
  return { ...headers, authorization: `Bearer ${token}` };
}

export function requestHasServiceToken(request, token, url = null) {
  const header = request.headers.authorization;
  const supplied = typeof header === "string" && header.startsWith("Bearer ")
    ? header.slice(7)
    : url?.searchParams.get("token") ?? "";
  const expectedBuffer = Buffer.from(token);
  const suppliedBuffer = Buffer.from(supplied);
  return suppliedBuffer.length === expectedBuffer.length && timingSafeEqual(suppliedBuffer, expectedBuffer);
}

export function isTrustedBrowserOrigin(request, endpoint) {
  const site = request.headers["sec-fetch-site"];
  if (site !== "same-origin") return false;
  const origin = request.headers.origin;
  return !origin || origin === endpoint;
}
