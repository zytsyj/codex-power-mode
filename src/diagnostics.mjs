const RECENT_ACTIVITY_MS = 5 * 60_000;

export function connectionDiagnostics({ health, nativePid, state, now = Date.now() }) {
  const lastRealEvent = health?.activity?.lastRealEvent ?? null;
  const lastRealAt = Date.parse(lastRealEvent?.timestamp ?? "");
  const ageMs = Number.isFinite(lastRealAt) ? Math.max(0, now - lastRealAt) : null;
  const hudConnected = Boolean(health && (health.clients ?? 0) > 0);
  const nativeOverlayRunning = Number.isInteger(nativePid) && nativePid > 0;
  const hookActivity = !health
    ? "offline"
    : !lastRealEvent
      ? "waiting-for-task"
      : ageMs <= RECENT_ACTIVITY_MS
        ? "receiving"
        : "idle";

  return {
    status: !health ? "offline" : !hudConnected ? "service-only" : hookActivity,
    hudConnected,
    nativeOverlayRunning,
    hookActivity,
    currentSessionId: state?.sessionId ?? health?.session?.activeSessionId ?? null,
    lastRealEventAt: lastRealEvent?.timestamp ?? null,
    lastRealEventAgeMs: ageMs,
    lastRealEventSessionId: lastRealEvent?.sessionId ?? null,
    sessionMatchesLastEvent: Boolean(state?.sessionId && lastRealEvent?.sessionId && state.sessionId === lastRealEvent.sessionId)
  };
}
