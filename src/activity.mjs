export function createActivityTracker() {
  let eventsReceived = 0;
  let realEventsReceived = 0;
  let lastEvent = null;
  let lastRealEvent = null;

  return {
    record(event) {
      const summary = {
        type: event?.type ?? null,
        timestamp: event?.timestamp ?? null,
        sessionId: event?.sessionId ?? null
      };
      eventsReceived += 1;
      lastEvent = summary;
      if (summary.sessionId && summary.sessionId !== "demo") {
        realEventsReceived += 1;
        lastRealEvent = summary;
      }
    },
    snapshot() {
      return { eventsReceived, realEventsReceived, lastEvent, lastRealEvent };
    }
  };
}
