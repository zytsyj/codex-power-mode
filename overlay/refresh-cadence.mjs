export function refreshDelayForState({
  previewMode = false,
  connectionOnline = false,
  hudHidden = false,
  comboChanging = false,
  momentumChanging = false
} = {}) {
  if (!previewMode && connectionOnline && hudHidden) return null;
  if (comboChanging) return 100;
  if (momentumChanging) return 250;
  return 1_000;
}
