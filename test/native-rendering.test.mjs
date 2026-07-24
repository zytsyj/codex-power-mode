import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const overlaySource = new URL("../native/macos/PowerModeOverlay.swift", import.meta.url);
const controllerSource = new URL("../scripts/power-mode.mjs", import.meta.url);
const nativeInfoSource = new URL("../native/macos/Info.plist", import.meta.url);

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
  assert.match(source, /for effects in \[energyEffects, semanticEffects\]/);
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
  assert.match(source, /phaseRail\.opacity = 0/);
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

test("native HUD is directly draggable while empty overlay space stays click-through", async () => {
  const source = await readFile(overlaySource, "utf8");

  assert.match(source, /guard shouldShowHUD\(now: Date\(\)\) else \{ return false \}/);
  assert.match(source, /if !positioning \{ beginPositioning\(\) \}/);
  assert.match(source, /installStatusItem\(\)[\s\S]*installMouseMonitors\(\)[\s\S]*updateMouseCapture\(\)/);
  assert.match(source, /panel\.ignoresMouseEvents = !view\.hudContains\(windowPoint: windowPoint\)/);
  assert.doesNotMatch(source, /guard positioning, let panel = window, let view = panel\.contentView as\? PowerModeView else \{ return \}/);
});

test("native settings menu avoids synchronous rebuilds and no longer exposes position controls", async () => {
  const source = await readFile(overlaySource, "utf8");

  assert.match(source, /func menuWillOpen\(_ menu: NSMenu\) \{\s+statusMenuIsOpen = true\s+removeMouseMonitors\(\)\s+refreshStatusMenu\(\)/);
  assert.match(source, /func menuDidClose\(_ menu: NSMenu\)[\s\S]*installMouseMonitors\(\)[\s\S]*if menuNeedsRebuild/);
  assert.match(source, /private func requestMenuRebuild\(\)/);
  assert.match(source, /DispatchQueue\.main\.async/);
  assert.doesNotMatch(source, /func menuWillOpen\(_ menu: NSMenu\) \{ rebuildMenu\(\) \}/);
  assert.doesNotMatch(source, /preferences\.text\("Position preset", "位置预设"\)/);
  assert.doesNotMatch(source, /preferences\.text\("Adjust position…", "调整位置…"\)/);
  assert.doesNotMatch(source, /preferences\.text\("Reset position", "重置位置"\)/);
});

test("Accessibility onboarding uses a stable app identity and activates without restarting", async () => {
  const [overlay, controller, info] = await Promise.all([
    readFile(overlaySource, "utf8"),
    readFile(controllerSource, "utf8"),
    readFile(nativeInfoSource, "utf8")
  ]);

  assert.match(info, /<string>Codex Power Mode<\/string>/);
  assert.match(info, /<string>com\.codexpowermode\.overlay<\/string>/);
  assert.match(info, /<key>LSUIElement<\/key>\s*<true\/>/);
  assert.match(controller, /Codex Power Mode\.app/);
  assert.match(controller, /CODEX_POWER_MODE_CODESIGN_IDENTITY/);
  assert.match(controller, /legacyNativeBinary/);
  assert.match(controller, /acceptedNativeBinaries/);
  assert.match(overlay, /kAXTrustedCheckOptionPrompt/);
  assert.match(overlay, /Privacy_Accessibility/);
  assert.match(overlay, /startPermissionPolling/);
  assert.match(overlay, /self\.startEventMonitoring\(\)/);
  assert.match(overlay, /preferences\.text\("Grant cursor access…", "授权光标效果…"\)/);
});

test("classic Power Mode hides the orb and centers cursor-driven Typing Combo", async () => {
  const source = await readFile(overlaySource, "utf8");

  assert.match(source, /private var classicMode: Bool \{ preferences\.settings\.preset == "classic" \}/);
  assert.match(source, /if value == "classic" \{ \$0\.typingCombo = true \}/);
  assert.match(source, /orbRenderer\.setVisible\(false, animated: false\)/);
  assert.match(source, /typingRenderer\.layout\(in: bounds, beside: hudRect, centered: classicMode\)/);
  assert.match(source, /if classicMode \{ return positioning \|\| typingComboProgress\(now: now\) > 0 \}/);
  assert.match(source, /typingRenderer\.showPositioningAnchor\(\)/);
  assert.match(source, /typingRenderer\.clearCombo\(\)/);
  assert.match(source, /Classic Power Mode · cursor \+ typing Combo/);
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
  assert.match(source, /persisted\.settings\.preset == "classic"/);
  assert.match(source, /persisted\.settings\.inactiveBehavior == "follow"/);
  assert.match(source, /persisted\.settings\.cursorEffect == "elegant"/);
  assert.match(source, /reset\.settings\.positionX == nil/);
});

test("native HUD enforces a peak layer and animation budget", async () => {
  const source = await readFile(overlaySource, "utf8");

  assert.match(source, /private func layerTreeMetrics/);
  assert.match(source, /private func runLayerBudgetSelfTest/);
  assert.match(source, /CODEX_POWER_MODE_LAYER_BUDGET_SELF_TEST/);
  assert.match(source, /CODEX_POWER_MODE_SYSTEM_REDUCE_MOTION_OVERRIDE/);
  assert.match(source, /var reduceMotionEnabled: Bool/);
  assert.match(source, /systemReduceMotionOverride \?\? NSWorkspace\.shared\.accessibilityDisplayShouldReduceMotion/);
  assert.match(source, /fflush\(stdout\)/);
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
  assert.match(source, /case "orbit":/);
  assert.match(source, /case "ripple":/);
  assert.match(source, /case "prism":/);
  assert.match(source, /case "wormhole":/);
  assert.match(source, /case "glitch":/);
  assert.match(source, /case "tentacle":/);
  assert.match(source, /case "meme":/);
  assert.match(source, /case "possum":/);
  assert.match(source, /case "freshcat":/);
  assert.match(source, /case "knifeshield":/);
  assert.match(source, /case "elegant":/);
  assert.match(source, /forKey: "cursor-orbit-arc"/);
  assert.match(source, /forKey: "cursor-orbit-particle"/);
  assert.match(source, /forKey: "cursor-ripple-core"/);
  assert.match(source, /forKey: "cursor-ripple-ring"/);
  assert.match(source, /forKey: "cursor-prism-core"/);
  assert.match(source, /forKey: "cursor-prism-ray"/);
  assert.match(source, /forKey: "cursor-wormhole-loop"/);
  assert.match(source, /forKey: "cursor-glitch-shard"/);
  assert.match(source, /forKey: "cursor-tentacle-arm"/);
  assert.match(source, /let words = \["典", "急", "孝", "乐", "绷", "赢"\]/);
  assert.match(source, /private weak var activeMemeText: CATextLayer\?/);
  assert.match(source, /activeMemeText\?\.removeAllAnimations\(\)/);
  assert.match(source, /activeMemeText\?\.removeFromSuperlayer\(\)/);
  assert.match(source, /forKey: "cursor-meme-word"/);
  assert.match(source, /private weak var activePossumSticker: CALayer\?/);
  assert.match(source, /hands-behind-possum-cutout\.png/);
  assert.match(source, /macOS input-method candidates normally open above the insertion point/);
  assert.match(source, /y: point\.y - \(milestone \? 48 : 42\)/);
  assert.match(source, /forKey: "cursor-possum-inspect"/);
  assert.match(source, /private weak var activeFreshCatSticker: CALayer\?/);
  assert.match(source, /fresh-cat-cutout\.png/);
  assert.match(source, /forKey: "cursor-fresh-cat-press"/);
  assert.match(source, /private weak var activeKnifeShieldDog: CALayer\?/);
  assert.match(source, /knife-shield-dog-cutout\.png/);
  assert.match(source, /forKey: "cursor-knife-shield-dog-waddle"/);
  assert.match(source, /private weak var activeElegantPerson: CALayer\?/);
  assert.match(source, /elegant-person-cutout\.png/);
  assert.match(source, /forKey: "cursor-elegant-person-bow"/);
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

  assert.match(source, /private final class EnergyEvolutionRenderer/);
  assert.match(source, /values\.append\(contentsOf: rising \? \[1, 1, 0, 0\] : \[0, 0, 1, 1\]\)/);
  assert.match(source, /forKey: rising \? "stage-fill-reset" : "stage-drain-restore"/);
  assert.match(source, /pulse\.values = rising \? \[1, 0\.98, 0\.96, 1\.055, 1\]/);
  assert.match(source, /playBreakthrough\(color: color, rising: rising/);
  assert.match(source, /forKey: rising \? "energy-breakthrough" : "energy-release"/);
  assert.match(source, /animateTopologyChange\(/);
  assert.match(source, /forKey: rising \? "energy-topology-assemble" : "energy-topology-release"/);
  assert.match(source, /forKey: "energy-node-migrate-\\\(index\)"/);
  assert.match(source, /group\.fillMode = \.backwards/);
  assert.match(source, /transition-\\\(variant\.name\)-\\\(theme\)-\\\(crossing\.label\)\.png/);
});

test("five energy tiers evolve one connected mechanism and settle into a static topology", async () => {
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
  assert.match(source, /if momentum < 900 \{ return 4 \}/);
  assert.match(source, /\(700, 899\), \(900, 999\)/);
  assert.match(source, /private struct TierBlueprint/);
  assert.match(source, /private struct ArcSpec/);
  assert.match(source, /private func blueprint\(for tier: Int\)/);
  assert.match(source, /private func path\(for arcs: \[ArcSpec\]\)/);
  assert.match(source, /private func driveGraphPath\(\)/);
  assert.match(source, /let upperLeft = nodePosition\(index: 1, tier: 3\)/);
  assert.match(source, /let upperRight = nodePosition\(index: 0, tier: 3\)/);
  assert.match(source, /let lowerRight = nodePosition\(index: 2, tier: 3\)/);
  assert.match(source, /let lowerLeft = nodePosition\(index: 3, tier: 3\)/);
  assert.match(source, /CGPoint\(x: 64, y: 57\),[\s\S]*?CGPoint\(x: 28, y: 57\),[\s\S]*?CGPoint\(x: 64, y: 35\),[\s\S]*?CGPoint\(x: 28, y: 35\)/);
  assert.match(source, /control1: CGPoint\(x: 35, y: 70\),[\s\S]*?control2: CGPoint\(x: 57, y: 70\)/);
  assert.match(source, /control1: CGPoint\(x: 35, y: 22\),[\s\S]*?control2: CGPoint\(x: 57, y: 22\)/);
  assert.match(source, /bus\.path = tier == 3 \? driveGraphPath\(\) : path\(for: blueprint\.busArcs\)/);
  assert.match(source, /let nodeSize: CGFloat = tier == 3 \? 4\.6 : 5\.6/);
  assert.match(source, /private func portPath/);
  assert.match(source, /private func stabilizerPath/);
  assert.match(source, /private func crownPath/);
  assert.match(source, /nodeRadius: 24,[\s\S]*?nodeAngles: \[330\]/);
  assert.match(source, /nodeRadius: 26,[\s\S]*?nodeAngles: \[90, 210, 330\]/);
  assert.match(source, /nodeRadius: 26,[\s\S]*?nodeAngles: \[30, 150, 210, 330\]/);
  assert.match(source, /nodeRadius: 29,[\s\S]*?nodeAngles: \[30, 90, 150, 210, 270, 330\]/);
  assert.match(source, /chassis\.opacity = tier == 1 \? 0\.9 : 0/);
  assert.match(source, /ports\.opacity = blueprint\.showsPorts \? 0\.72 : 0/);
  assert.match(source, /stabilizer\.opacity = blueprint\.showsLocks \? 0\.78 : 0/);
  assert.match(source, /crown\.opacity = blueprint\.showsCrown \? 1 : 0/);
  assert.match(source, /bus\.lineDashPattern = nil/);
  assert.match(source, /visibleNodeCount\(tier: tier\)/);
  assert.match(source, /updateMotion\(tier: tier, phase: phase/);
  assert.match(source, /key\.hasPrefix\("energy-steady-"\)/);
  assert.doesNotMatch(source, /private func animateNodes\(/);
  assert.doesNotMatch(source, /private func addNodePulse\(/);
  assert.doesNotMatch(source, /energy-steady-[a-z-]+node/);
  assert.doesNotMatch(source, /"energy-steady-drive-flow"/);
  assert.doesNotMatch(source, /"energy-steady-critical-lock"/);
  assert.doesNotMatch(source, /"energy-steady-peak-sync"/);
  assert.doesNotMatch(source, /energy-steady-critical-counter/);
  assert.doesNotMatch(source, /modules\.forEach \{ \$0\.removeAllAnimations\(\) \}/);
  assert.doesNotMatch(source, /overloadVentPath/);
  assert.doesNotMatch(source, /energy-tier-breath/);
  assert.match(source, /CGPoint\(x: 18, y: 46\)/);
  assert.match(source, /CGPoint\(x: 74, y: 46\)/);
  assert.doesNotMatch(source, /CGPoint\(x: 57, y: 39\)/);
  assert.doesNotMatch(source, /lastPhase/);
  assert.doesNotMatch(source, /if phase == "act" \{ ports\.opacity = 0 \}/);
  assert.match(source, /case "act":\s+break/);
  assert.match(source, /private func playActArrow\(color: NSColor\)/);
  assert.match(source, /CGPoint\(x: 10, y: 39\)[\s\S]*?CGPoint\(x: 86, y: 46\)[\s\S]*?CGPoint\(x: 10, y: 53\)[\s\S]*?path\.closeSubpath\(\)/);
  assert.match(source, /playActArrow\(color: color\)/);
  assert.match(source, /animateActClearance\(duration: duration, reducedMotion: reducedMotion\)/);
  assert.match(source, /arrow\.add\(group, forKey: "act-arrow-pass"\)/);
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
  assert.match(source, /private final class ComboArcRenderer/);
  assert.doesNotMatch(source, /private let comboEffects = CALayer\(\)/);
  assert.match(source, /semanticEffects\.sublayers\?\.forEach \{ \$0\.removeFromSuperlayer\(\) \}/);
  assert.match(source, /private func updateSemanticContrast\(phase: String, tier: Int, color: NSColor\)/);
  assert.match(source, /signatureBackdrop\.lineWidth = signature\.lineWidth \+ \(highEnergy \? 3\.6 : 2\.5\)/);
  assert.match(source, /phaseRailBackdrop\.lineWidth = phaseRail\.lineWidth \+ \(highEnergy \? 3\.1 : 2\.3\)/);
  assert.match(source, /private func animateSemanticReveal\(phase: String, tier: Int\)/);
  assert.doesNotMatch(source, /animatePhaseCue/);
  assert.match(source, /private func animateCoreEvent\(_ phase: String\)/);
  assert.match(source, /scaleX\.values = \[1, 0\.87, 1\.18, 0\.96, 1\.06, 1\]/);
  assert.match(source, /rotation\.values = \[0, -0\.14, 0\.1, -0\.055, 0\.018, 0\]/);
  assert.doesNotMatch(source, /core-state-impact/);
  assert.match(source, /innerGroup\.repeatCount = phase == "complete" \? 1 : \.infinity/);
  assert.match(source, /sheenGroup\.repeatCount = phase == "complete" \? 1 : \.infinity/);
  assert.match(source, /light\.repeatCount = phase == "complete" \? 1 : \.infinity/);
  assert.match(source, /signature\.add\(animation, forKey: "signature-phase"\)/);
  assert.match(source, /forKey: "semantic-energy-duck"/);
  assert.match(source, /forKey: "semantic-reveal"/);
  assert.doesNotMatch(source, /forKey: "semantic-rail-reveal"/);
  assert.match(source, /forKey: "semantic-glyph-reveal"/);
  assert.match(source, /configureGauge\(ring, width: 5\.2\)/);
  assert.match(source, /configureRing\(phaseRail, radius: 32\.2/);
  assert.match(source, /private func phaseRailPath\(_ phase: String\)/);
  assert.match(source, /phaseRailBackdrop\.path = phaseRailPath\(phase\)/);
  assert.match(source, /phaseRail\.path = phaseRailPath\(phase\)/);
  assert.match(source, /phaseRail\.lineDashPattern = nil/);
  assert.match(source, /signature\.opacity = active \? 1 : 0\.36/);
  assert.match(source, /signatureBackdrop\.opacity = active \? \(phase == "complete" \? 0\.7 : highEnergy \? 0\.5 : 0\.28\)/);
  assert.match(source, /signature\.path = coreSignaturePath\(phase, completion: completion\)/);
  assert.match(source, /case "unverified":/);
  assert.match(source, /case "cancelled":/);
  assert.match(source, /completionStyle != state\.completion/);
});

test("native HUD arbitrates transient animation instead of stacking every effect family", async () => {
  const source = await readFile(overlaySource, "utf8");

  assert.match(source, /private enum VisualPriority: Int/);
  assert.match(source, /case terminal = 4/);
  assert.match(source, /private func beginVisualTransition/);
  assert.match(source, /priority\.rawValue < activeVisualPriority\.rawValue/);
  assert.match(source, /semanticEffects\.sublayers\?\.forEach \{ \$0\.removeFromSuperlayer\(\) \}/);
  assert.match(source, /emitter\.emitterCells = nil/);
  assert.match(source, /beatRing\.removeAllAnimations\(\)/);
  assert.match(source, /energyVisuals\.setCompletionEmphasis\(nextPhase == "complete"\)/);
  assert.match(source, /configureArc\(comboRing, radius: 43\.5/);
  assert.match(source, /let startProgress = hadVisibleArc \? min\(displayedProgress, logicalProgress\) : logicalProgress/);
  assert.match(source, /if grew, !reducedMotion, logicalProgress - startProgress > 0\.01/);
  assert.match(source, /refill\.values = \[startProgress, logicalProgress, logicalProgress, 0\]/);
  assert.match(source, /arc\.add\(refill, forKey: "combo-arc-refill-decay-\\\(currentGeneration\)"\)/);
  assert.match(source, /decay\.fromValue = startProgress/);
  assert.match(source, /arc\.add\(decay, forKey: "combo-arc-decay-\\\(currentGeneration\)"\)/);
  assert.doesNotMatch(source, /combo-growth-wave/);
  assert.match(source, /mixOrbit\.lineDashPattern = nil/);
  assert.match(source, /private func updateMixOrbit[\s\S]*?mixOrbit\.opacity = 0[\s\S]*?mixOrbit\.removeAllAnimations\(\)/);
  assert.doesNotMatch(source, /mixOrbit\.lineDashPattern = \[2, 7\]/);
  assert.match(source, /let colors: \[NSColor\] = \[[\s\S]*?\.systemGreen,[\s\S]*?NSColor\.white\.withAlphaComponent\(0\.82\),[\s\S]*?NSColor\.systemGreen\.withAlphaComponent\(0\.58\)/);
  assert.match(source, /animateEventRhythm\(event, phase: nextPhase, color: color\)/);
  assert.match(source, /playSemanticChoreography\(phase: nextPhase, completion: state\.completion, color: color\)/);
  assert.match(source, /emitFeedback\(for: event, phase: nextPhase, color: color\)/);
  assert.match(source, /case "observe": playObserveCapture\(color: color\)/);
  assert.match(source, /case "act":[\s\S]*?playActArrow\(color: color\)[\s\S]*?playActDrive\(color: color\)/);
  assert.match(source, /case "verify": playVerifyConvergence\(color: color\)/);
  assert.match(source, /case "wait": playWaitGates\(color: color\)/);
  assert.match(source, /case "recover": playRecoverFragments\(color: color\)/);
  assert.match(source, /case "complete": playCompleteFamily\(completion: completion\)/);
  assert.match(source, /if reducedMotion \{[\s\S]*?if phase == "complete" \{ playCompleteFamily\(completion: completion\) \}/);
  assert.match(source, /confirmation\.opacity = 0\.84/);
  assert.match(source, /let highEnergy = tier >= 4/);
  assert.match(source, /let peakEnergy = tier >= 5/);
});
