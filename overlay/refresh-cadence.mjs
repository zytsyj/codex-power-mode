export function refreshDelayForState({
  previewMode = false,
  connectionOnline = false,
  hudHidden = false,
  comboChanging = false,
  momentumChanging = false
} = {}) {
  if (!previewMode && connectionOnline && hudHidden) return null;
  return comboChanging || momentumChanging ? 100 : 1_000;
}
