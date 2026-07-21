const DEFAULT_LEASE_MS = 30_000;

function eventTime(event, fallback) {
  const parsed = Date.parse(event?.timestamp ?? "");
  return Number.isFinite(parsed) ? parsed : fallback;
}

function isTerminalState(state) {
  return state?.status === "complete" || state?.status === "idle" || state?.phase === "idle";
}

export function createSessionArbiter(initialState = {}, { leaseMs = DEFAULT_LEASE_MS, now = Date.now } = {}) {
  let activeSessionId = initialState?.sessionId ?? null;
  let activeSessionSource = initialState?.sessionSource ?? "unknown";
  let activeAt = Math.max(
    Date.parse(initialState?.lastActivityAt ?? "") || 0,
    Date.parse(initialState?.turnStoppedAt ?? "") || 0
  );
  let activeStopped = isTerminalState(initialState);
  let lastSwitchAt = activeSessionId ? activeAt || now() : null;
  let suppressedEvents = 0;

  return {
    consider(event, { mode = "focused" } = {}) {
      const sessionId = event?.sessionId ?? null;
      const sessionSource = event?.sessionSource ?? "unknown";
      const at = eventTime(event, now());

      if (!sessionId || sessionId === "demo") return { displayed: true, switched: false };

      if (sessionId === activeSessionId) {
        if (at < activeAt) {
          suppressedEvents += 1;
          return { displayed: false, switched: false };
        }
        activeAt = at;
        if (sessionSource !== "unknown") activeSessionSource = sessionSource;
        activeStopped = event.type === "turn-stop";
        return { displayed: true, switched: false };
      }

      if (mode === "global") {
        if (at < activeAt) {
          suppressedEvents += 1;
          return { displayed: false, switched: false };
        }
        activeSessionId = sessionId;
        activeSessionSource = sessionSource;
        activeAt = at;
        activeStopped = event.type === "turn-stop";
        lastSwitchAt = at;
        return { displayed: true, switched: true };
      }

      const leaseExpired = at - activeAt >= leaseMs;
      if (!activeSessionId || activeStopped || leaseExpired) {
        const switched = activeSessionId !== sessionId;
        activeSessionId = sessionId;
        activeSessionSource = sessionSource;
        activeAt = at;
        activeStopped = event.type === "turn-stop";
        if (switched) lastSwitchAt = at;
        return { displayed: true, switched };
      }

      suppressedEvents += 1;
      return { displayed: false, switched: false };
    },

    snapshot() {
      return { activeSessionId, activeSessionSource, lastSwitchAt, suppressedEvents, leaseMs };
    }
  };
}
