import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const overlaySource = new URL("../native/macos/PowerModeOverlay.swift", import.meta.url);
const controllerSource = new URL("../scripts/power-mode.mjs", import.meta.url);

test("native HUD uses compositor-driven orb layers instead of frame-by-frame drawing", async () => {
  const source = await readFile(overlaySource, "utf8");

  assert.match(source, /private func invalidateVisuals/);
  assert.match(source, /private final class OrbLayerRenderer/);
  assert.match(source, /private let usesCompositorRenderer = true/);
  assert.match(source, /CAEmitterLayer/);
  assert.match(source, /CABasicAnimation\(keyPath: "strokeEnd"\)/);
  assert.match(source, /private let beatRing = CAShapeLayer\(\)/);
  assert.match(source, /private func animateEventRhythm/);
  assert.match(source, /private func playBeatRing/);
  assert.match(source, /private let semanticEffects = CALayer\(\)/);
  assert.match(source, /private func playObserveCapture/);
  assert.match(source, /private func playActDrive/);
  assert.match(source, /private func playVerifyConvergence/);
  assert.match(source, /private func playWaitGates/);
  assert.match(source, /private func playRecoverFragments/);
  assert.match(source, /private func playCompleteFamily/);
  assert.match(source, /private func playCompleteOutcome/);
  assert.match(source, /private func playMixCompletion/);
  assert.match(source, /mix-complete-closure/);
  assert.match(source, /mix-complete-outcome/);
  assert.match(source, /mix-complete-stamp/);
  assert.match(source, /preferences\.text\("1 DONE\/OK", "一项已验证"\)/);
  assert.match(source, /complete-family-closure/);
  assert.match(source, /complete-verified-reward/);
  assert.match(source, /complete-unverified-gap/);
  assert.match(source, /complete-cancelled-retract/);
  assert.match(source, /complete-no-change-settle/);
  assert.match(source, /preferences\.text\("COMPLETE", "完成"\)/);
  assert.match(source, /preferences\.text\("DONE\/OK", "完成\/已验证"\)/);
  assert.match(source, /preferences\.text\("DONE\/CHECK", "完成\/待验证"\)/);
  assert.match(source, /preferences\.text\("DONE\/CANCEL", "完成\/已取消"\)/);
  assert.match(source, /preferences\.text\("DONE\/NO CHANGE", "完成\/无修改"\)/);
  assert.match(source, /activity\.masksToBounds = true/);
  assert.match(source, /private func activityFontSize/);
  assert.match(source, /for effects in \[energyEffects, semanticEffects, comboEffects\]/);
  assert.match(source, /forKey: "evidence-track"/);
  assert.match(source, /layer\.compositingFilter = "screenBlendMode"/);
  assert.match(source, /private func animateParticleAlongPath/);
  assert.match(source, /position\.calculationMode = \.paced/);
  assert.match(source, /position\.rotationMode = \.rotateAuto/);
  assert.match(source, /private let body = CALayer\(\)/);
  assert.match(source, /private let sheen = CAGradientLayer\(\)/);
  assert.match(source, /private func animateCorePhase/);
  assert.match(source, /private func animateCoreEvent/);
  assert.match(source, /private let signature = CAShapeLayer\(\)/);
  assert.match(source, /private func updateCoreSignature/);
  assert.match(source, /private func coreSignaturePath/);
  assert.match(source, /private let phaseRail = CAShapeLayer\(\)/);
  assert.match(source, /phaseRail\.lineDashPattern/);
  assert.match(source, /restingRailOpacity: Float = phase == "complete" \? 0\.72 : 0/);
  assert.match(source, /phaseRail\.opacity = active && phase == "complete" \? 0\.72 : 0/);
  assert.doesNotMatch(source, /phaseRail\.add\(dash, forKey: "phase-dash"\)/);
  assert.match(source, /pulse\.keyTimes = \[0, 0\.1, 0\.2, 0\.32, 0\.44, 1\]/);
  assert.match(source, /private func hudBaseSize\(expanded: Bool\? = nil\) -> CGSize \{ CGSize\(width: 92, height: 92\) \}/);
  assert.match(source, /effectIntensity > 1\.2 \? 30 : 45/);
  assert.match(source, /let frameStep = max/);
  assert.match(source, /context\.clear\(dirtyRect\)/);
  assert.doesNotMatch(source, /context\.clear\(bounds\)/);
  assert.doesNotMatch(source, /context\.fill\(bounds\)/);
  assert.doesNotMatch(source, /particle\.color\.withAlphaComponent/);
  assert.doesNotMatch(source, /\("always", preferences\.text\("Always expanded"/);
  assert.match(source, /let settledAt = idleAt\.addingTimeInterval\(45\)/);
  assert.doesNotMatch(source, /hasEffects \|\| positioning \|\| comboIsDecaying \|\| hudIsFading \|\| presentation\.returning/);
});

test("Complete showcase previews the shared family without changing real state", async () => {
  const source = await readFile(controllerSource, "utf8");

  assert.match(source, /async function playCompletionShowcase/);
  assert.match(source, /completion: "verified"/);
  assert.match(source, /completion: "unverified"/);
  assert.match(source, /completion: "cancelled"/);
  assert.match(source, /completion: "no-change"/);
  assert.match(source, /finally \{\s+await restorePreview\(realState\);/);
});

test("native event stream applies bounded exponential reconnect backoff", async () => {
  const source = await readFile(overlaySource, "utf8");

  assert.match(source, /private let reconnectStableWindow: TimeInterval = 10/);
  assert.match(source, /private func reconnectDelay\(for attempt: Int\)/);
  assert.match(source, /min\(30, pow\(2, Double\(max\(0, attempt\)\)\)\)/);
  assert.match(source, /\(0\.\.\.7\)\.map\(reconnectDelay\) == \[1, 2, 4, 8, 16, 30, 30, 30\]/);
  assert.match(source, /connectedDuration >= reconnectStableWindow/);
  assert.match(source, /CODEX_POWER_MODE_RECONNECT_SELF_TEST/);
  assert.match(source, /reconnectAttempt = reconnectAttemptAfterConnection/);
});

test("native HUD settings self-test exercises isolated persistence and validation", async () => {
  const source = await readFile(overlaySource, "utf8");

  assert.match(source, /private func runSettingsPersistenceSelfTest/);
  assert.match(source, /CODEX_POWER_MODE_SETTINGS_SELF_TEST/);
  assert.match(source, /func setEnergyGainMultiplier\(_ value: Double\)/);
  assert.match(source, /let supported = \[0\.3, 0\.4, 0\.5, 0\.6, 0\.72, 0\.85, 1\.0, 1\.15, 1\.3, 1\.5\]/);
  assert.match(source, /preferences\.text\("Energy gain", "能量获取"\)/);
  assert.match(source, /#selector\(selectEnergyGainMultiplier\)/);
  assert.match(source, /CODEX_POWER_MODE_CONFIG_PATH/);
  assert.match(source, /func reloaded\(\) -> PowerModePreferences/);
  assert.match(source, /let persisted = reloaded\(\)/);
  assert.match(source, /persisted\.settings\.activitySource == "mix"/);
  assert.match(source, /persisted\.settings\.inactiveBehavior == "follow"/);
  assert.match(source, /persisted\.settings\.cursorEffect == "neon"/);
  assert.match(source, /reset\.settings\.positionX == nil/);
});

test("native HUD enforces a peak layer and animation budget", async () => {
  const source = await readFile(overlaySource, "utf8");

  assert.match(source, /private func layerTreeMetrics/);
  assert.match(source, /private func runLayerBudgetSelfTest/);
  assert.match(source, /CODEX_POWER_MODE_LAYER_BUDGET_SELF_TEST/);
  assert.match(source, /let budgets = LayerTreeMetrics\(layers: 96, animations: 88\)/);
  assert.match(source, /reduced\.layers < focus\.layers/);
  assert.match(source, /reduced\.animations < focus\.animations/);
});

test("typing Combo follows the foreground Codex app without relying on an AX text role", async () => {
  const source = await readFile(overlaySource, "utf8");

  assert.match(source, /private func isCodexFrontmost\(\) -> Bool/);
  assert.match(source, /app\.bundleIdentifier == codexBundleIdentifier/);
  assert.match(source, /CGEvent\.tapCreate/);
  assert.match(source, /options: \.listenOnly/);
  assert.match(source, /CGEvent\.tapEnable/);
  assert.doesNotMatch(source, /isCodexComposerFocused/);
  assert.match(source, /\[48, 51, 53, 117, 123, 124, 125, 126\]/);
  assert.match(source, /if \[36, 76\]\.contains\(keyCode\)/);
  assert.doesNotMatch(source, /handleTypingSubmit/);
  assert.match(source, /event\.toolGroup == "prompt"/);
  assert.match(source, /DispatchQueue\.main\.asyncAfter\(deadline: \.now\(\) \+ 0\.03\)/);
  assert.match(source, /precedingCharacter = CFRange/);
  assert.match(source, /"AXSelectedTextMarkerRange"/);
  assert.match(source, /"AXBoundsForTextMarkerRange"/);
  assert.match(source, /"AXEndTextMarkerForTextMarkerRange"/);
  assert.match(source, /"AXTextMarkerRangeForUnorderedTextMarkers"/);
  assert.match(source, /"AXPreviousTextMarkerForTextMarker"/);
  assert.match(source, /kAXFocusedWindowAttribute/);
  assert.match(source, /elementSupportsCaretBounds/);
  assert.doesNotMatch(source, /fallbackComposerPoint/);
  assert.doesNotMatch(source, /focusedElementFallback/);
  assert.match(source, /private final class TypingFeedbackRenderer/);
  assert.match(source, /private func caretScreenPoint\(\) -> CGPoint\?/);
  assert.match(source, /private func isUsableCaretBounds/);
  assert.match(source, /CODEX_POWER_MODE_ACCESSIBILITY_SELF_TEST/);
  assert.match(source, /bounds\.width > 0 \|\| bounds\.height > 0/);
  assert.match(source, /cachedCaretElement = nil/);
  assert.match(source, /"AXManualAccessibility"/);
  assert.match(source, /"AXEnhancedUserInterface"/);
  assert.match(source, /private func caretBounds\(startingAt element: AXUIElement\)/);
  assert.match(source, /forKey: neon \? "caret-neon" : "caret-spark-glyph"/);
  assert.match(source, /forKey: "cursor-combo-milestone"/);
  assert.match(source, /let particleCount = neon/);
  assert.match(source, /typingRenderer\.inject\(to: reactorCenter\(\), count: count\)/);
  assert.match(source, /private let lifetimeFill = CAGradientLayer\(\)/);
  assert.match(source, /private func typingPalette\(for count: Int\)/);
  assert.match(source, /forKey: "typing-lifetime"/);
  assert.match(source, /CAKeyframeAnimation\(keyPath: "colors"\)/);
  assert.match(source, /typing-\\\(variant\.name\)-\\\(theme\)-\\\(comboSample\.label\)\.png/);
  assert.match(source, /forKey: "typing-collapse"/);
  assert.match(source, /forKey: "typing-converge"/);
  assert.match(source, /forKey: "typing-energy-stream"/);
});

test("energy tier crossings use a paced gauge and bounded breakthrough choreography", async () => {
  const source = await readFile(overlaySource, "utf8");

  assert.match(source, /private final class EnergyVisualRenderer/);
  assert.match(source, /values\.append\(contentsOf: rising \? \[1, 1, 0, 0\] : \[0, 0, 1, 1\]\)/);
  assert.match(source, /forKey: rising \? "stage-fill-reset" : "stage-drain-restore"/);
  assert.match(source, /pulse\.values = rising \? \[1, 1\.04, 0\.88, 0\.88, 1\.28, 0\.95, 1\.05, 1\]/);
  assert.match(source, /playBreakthrough\(color: color, rising: rising/);
  assert.match(source, /forKey: rising \? "energy-breakthrough" : "energy-release"/);
  assert.match(source, /animateTopologyChange\(/);
  assert.match(source, /forKey: rising \? "energy-topology-assemble" : "energy-topology-release"/);
  assert.match(source, /forKey: "energy-node-migrate-\\\(index\)"/);
  assert.match(source, /group\.fillMode = \.backwards/);
  assert.match(source, /transition-\\\(variant\.name\)-\\\(theme\)-\\\(crossing\.label\)\.png/);
});

test("five energy tiers evolve one connected mechanism with shared semantic motion", async () => {
  const source = await readFile(overlaySource, "utf8");

  assert.match(source, /private let mechanism = CALayer\(\)/);
  assert.match(source, /private let chassis = CAShapeLayer\(\)/);
  assert.match(source, /private let bus = CAShapeLayer\(\)/);
  assert.match(source, /private let ports = CAShapeLayer\(\)/);
  assert.match(source, /private let stabilizer = CAShapeLayer\(\)/);
  assert.match(source, /private let crown = CAShapeLayer\(\)/);
  assert.match(source, /private let nodes = \(0\.\.<6\)\.map/);
  assert.match(source, /if momentum < 200 \{ return 1 \}/);
  assert.match(source, /if momentum < 450 \{ return 2 \}/);
  assert.match(source, /if momentum < 700 \{ return 3 \}/);
  assert.match(source, /if momentum < 999 \{ return 4 \}/);
  assert.match(source, /private func driveBusPath/);
  assert.match(source, /private func portPath/);
  assert.match(source, /private func stabilizerPath/);
  assert.match(source, /private func crownPath/);
  assert.match(source, /visibleNodeCount\(tier: tier\)/);
  assert.match(source, /updateMotion\(tier: tier, phase: phase/);
  assert.match(source, /case "observe":/);
  assert.match(source, /case "act":/);
  assert.match(source, /case "verify":/);
  assert.match(source, /case "wait":/);
  assert.match(source, /case "recover":/);
  assert.match(source, /case "complete":/);
  assert.match(source, /private func animateNodes\(/);
  assert.match(source, /radialOffset: -7/);
  assert.match(source, /translation: CGPoint\(x: 4\.5, y: 0\)/);
  assert.match(source, /doubleBeat: true/);
  assert.match(source, /phase == "recover"/);
  assert.match(source, /"energy-steady-drive-flow"/);
  assert.match(source, /"energy-steady-critical-counter"/);
  assert.match(source, /"energy-steady-peak-sync"/);
  assert.doesNotMatch(source, /modules\.forEach \{ \$0\.removeAllAnimations\(\) \}/);
  assert.doesNotMatch(source, /overloadVentPath/);
  assert.doesNotMatch(source, /energy-tier-breath/);
  assert.match(source, /CGPoint\(x: 10, y: 35\)/);
  assert.match(source, /CGPoint\(x: 82, y: 35\)/);
  assert.doesNotMatch(source, /CGPoint\(x: 57, y: 39\)/);
  assert.match(source, /private func runEnergyRenderQA/);
  assert.match(source, /"CODEX_POWER_MODE_RENDER_QA_DIR"/);
  assert.match(source, /let tiers = \[90, 320, 580, 850, 999\]/);
  assert.match(source, /for phase in \["observe", "act", "verify", "wait", "recover", "complete"\]/);
  assert.match(source, /for momentum in \[90, 580, 850\]/);
  assert.match(source, /for completion in \["verified", "unverified", "cancelled", "no-change"\]/);
  assert.match(source, /neon-milestone/);
});

test("semantic phase grammar stays independent from energy progress and completion outcomes remain distinct", async () => {
  const source = await readFile(overlaySource, "utf8");

  assert.match(source, /private let energyEffects = CALayer\(\)/);
  assert.match(source, /private let semanticEffects = CALayer\(\)/);
  assert.match(source, /private let comboEffects = CALayer\(\)/);
  assert.match(source, /semanticEffects\.sublayers\?\.forEach \{ \$0\.removeFromSuperlayer\(\) \}/);
  assert.match(source, /private func updateSemanticContrast\(phase: String, tier: Int, color: NSColor\)/);
  assert.match(source, /signatureBackdrop\.lineWidth = signature\.lineWidth \+ \(highEnergy \? 3\.6 : 2\.5\)/);
  assert.match(source, /phaseRailBackdrop\.lineWidth = phaseRail\.lineWidth \+ \(highEnergy \? 3\.1 : 2\.3\)/);
  assert.match(source, /private func animateSemanticReveal\(phase: String, tier: Int\)/);
  assert.match(source, /forKey: "semantic-energy-duck"/);
  assert.match(source, /forKey: "semantic-reveal"/);
  assert.match(source, /forKey: "semantic-rail-reveal"/);
  assert.match(source, /forKey: "semantic-glyph-reveal"/);
  assert.match(source, /configureGauge\(ring, width: 5\.2\)/);
  assert.match(source, /configureRing\(phaseRail, radius: 32\.2/);
  assert.match(source, /private func phaseRailPath\(_ phase: String\)/);
  assert.match(source, /phaseRailBackdrop\.path = phaseRailPath\(phase\)/);
  assert.match(source, /phaseRail\.path = phaseRailPath\(phase\)/);
  assert.match(source, /phaseRail\.lineDashPattern = phase == "observe" \? \[4, 4\]/);
  assert.match(source, /phase == "recover" \? \[7, 4\]/);
  assert.match(source, /signature\.path = coreSignaturePath\(phase, completion: completion\)/);
  assert.match(source, /case "unverified":/);
  assert.match(source, /case "cancelled":/);
  assert.match(source, /completionStyle != state\.completion/);
});
