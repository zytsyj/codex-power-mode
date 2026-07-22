import { connectionDiagnostics } from "./diagnostics.mjs";
import { comboStage, energyLevel, presentationSnapshot } from "./state.mjs";

export function powerModeStatus({ health, nativePid, nativeConfiguration, state, endpoint }) {
  const presentation = presentationSnapshot(state);
  return {
    service: { running: Boolean(health), url: endpoint, ...(health ?? {}) },
    nativeOverlay: { running: Boolean(nativePid), pid: nativePid, configuration: nativeConfiguration },
    connection: connectionDiagnostics({ health, nativePid, state }),
    hudDisplay: {
      ...presentation,
      energyLevel: energyLevel(presentation.momentum),
      comboStage: comboStage(presentation)
    },
    taskState: state
  };
}
