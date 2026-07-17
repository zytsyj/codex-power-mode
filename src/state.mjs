export const initialState = Object.freeze({
  combo: 0,
  bestCombo: 0,
  score: 0,
  mode: "idle",
  edits: 0,
  addedLines: 0,
  removedLines: 0,
  verifications: 0,
  lastEditAt: null,
  lastVerificationAt: null,
  lastVerificationPassed: false,
  sessionId: null
});

function editPoints(event) {
  return Math.max(1, Math.min(50, Math.ceil(event.addedChars / 12) + event.addedLines * 2 + event.removedLines));
}

function verificationPoints(category) {
  return category === "test" ? 30 : category === "build" ? 20 : 10;
}

export function reduceState(previous = initialState, event) {
  const state = { ...initialState, ...previous, sessionId: event.sessionId ?? previous.sessionId };

  if (event.type === "edit") {
    const points = editPoints(event);
    state.combo += points;
    state.bestCombo = Math.max(state.bestCombo, state.combo);
    state.score += points;
    state.mode = state.combo >= 40 ? "power" : "combo";
    state.edits += 1;
    state.addedLines += event.addedLines;
    state.removedLines += event.removedLines;
    state.lastEditAt = event.timestamp;
    state.lastVerificationPassed = false;
  } else if (event.type === "verification") {
    state.verifications += 1;
    state.lastVerificationAt = event.timestamp;
    state.lastVerificationPassed = event.success;
    if (event.success) {
      const points = verificationPoints(event.category);
      state.combo += points;
      state.bestCombo = Math.max(state.bestCombo, state.combo);
      state.score += points;
      state.mode = "power";
    } else {
      state.combo = 0;
      state.mode = "danger";
    }
  } else if (event.type === "turn-stop") {
    const verifiedAfterEdit = state.lastVerificationPassed && state.lastVerificationAt &&
      (!state.lastEditAt || state.lastVerificationAt >= state.lastEditAt);
    state.mode = verifiedAfterEdit ? "victory" : state.edits ? "unverified" : "idle";
  }

  return state;
}
