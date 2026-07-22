import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const overlaySource = new URL("../native/macos/PowerModeOverlay.swift", import.meta.url);

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
  assert.match(source, /private let choreography = CALayer\(\)/);
  assert.match(source, /private func playObserveCapture/);
  assert.match(source, /private func playActDrive/);
  assert.match(source, /private func playVerifyConvergence/);
  assert.match(source, /private func playWaitGates/);
  assert.match(source, /private func playRecoverFragments/);
  assert.match(source, /private func playCompleteRings/);
  assert.match(source, /container\.insertSublayer\(choreography, above: beatRing\)/);
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
  assert.match(source, /phaseRail\.add\(dash, forKey: "phase-dash"\)/);
  assert.doesNotMatch(source, /energyRing\.add\(dash, forKey: "phase-dash"\)/);
  assert.match(source, /pulse\.keyTimes = \[0, 0\.1, 0\.2, 0\.32, 0\.44, 1\]/);
  assert.match(source, /private func hudBaseSize\(expanded: Bool\? = nil\) -> CGSize \{ CGSize\(width: 92, height: 92\) \}/);
  assert.match(source, /effectIntensity > 1\.2 \? 30 : 45/);
  assert.match(source, /let frameStep = max/);
  assert.match(source, /context\.clear\(dirtyRect\)/);
  assert.doesNotMatch(source, /context\.clear\(bounds\)/);
  assert.doesNotMatch(source, /context\.fill\(bounds\)/);
  assert.doesNotMatch(source, /particle\.color\.withAlphaComponent/);
  assert.doesNotMatch(source, /\("always", preferences\.text\("Always expanded"/);
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
  assert.match(source, /stageShell\.path = CGPath\(ellipseIn:/);
  assert.match(source, /forKey: "typing-lifetime"/);
  assert.match(source, /CAKeyframeAnimation\(keyPath: "backgroundColor"\)/);
  assert.match(source, /forKey: "typing-collapse"/);
  assert.match(source, /forKey: "typing-converge"/);
  assert.match(source, /forKey: "typing-energy-stream"/);
});

test("energy tier crossings use a complete multi-ring breakthrough choreography", async () => {
  const source = await readFile(overlaySource, "utf8");

  assert.match(source, /let compression = 0\.92 - Double\(tierStrength\) \* 0\.08/);
  assert.match(source, /let breakthrough = 1\.22 \+ Double\(tierStrength\) \* 0\.15/);
  assert.match(source, /ringValues\.append\(contentsOf: \[boundary, boundary, reset, reset\]\)/);
  assert.match(source, /forKey: rising \? "tier-ring-impact" : "tier-ring-collapse"/);
  assert.match(source, /let flareCount = rising \? min\(arcade \? 7 : 5, 2 \+ crossings \+ next \/ 2\) : 2/);
  assert.match(source, /forKey: rising \? "energy-breakthrough" : "energy-vent"/);
  assert.match(source, /forKey: "energy-tier-establish"/);
  assert.match(source, /transition-\\\(variant\.name\)-\\\(theme\)-\\\(crossing\.label\)\.png/);
});

test("all seven energy tiers have distinct material, node, texture, and motion profiles", async () => {
  const source = await readFile(overlaySource, "utf8");

  assert.match(source, /private func energyTierPalette/);
  assert.match(source, /let nodeCounts = \[0, 1, 3, 5, 8, 10, 14, 16\]/);
  assert.match(source, /case 4: stageShell\.lineDashPattern = \[15, 4\]/);
  assert.match(source, /case 7: tierAura\.lineDashPattern = \[3, 1\]/);
  assert.match(source, /private func energyTierNodePath/);
  assert.match(source, /private func updateEnergyTierMotion/);
  assert.match(source, /let spinDurations: \[CFTimeInterval\] = \[0, 12, 9, 6\.8, 4\.7, 3\.4, 2\.35, 5\.6\]/);
  assert.match(source, /forKey: "energy-tier-breath"/);
  assert.match(source, /forKey: "energy-node-orbit"/);
  assert.match(source, /private func runEnergyRenderQA/);
  assert.match(source, /"CODEX_POWER_MODE_RENDER_QA_DIR"/);
  assert.match(source, /let tiers = \[45, 170, 340, 580, 820, 960, 999\]/);
  assert.match(source, /for phase in \["observe", "act", "verify", "wait", "recover", "complete"\]/);
  assert.match(source, /for momentum in \[45, 580, 960\]/);
  assert.match(source, /for completion in \["verified", "unverified", "cancelled", "no-change"\]/);
  assert.match(source, /neon-milestone/);
});

test("semantic phase grammar stays independent from energy progress and completion outcomes remain distinct", async () => {
  const source = await readFile(overlaySource, "utf8");

  assert.match(source, /configureRing\(energyRing, radius: 35\.5/);
  assert.match(source, /configureRing\(phaseRail, radius: 32\.2/);
  assert.match(source, /phaseRail\.lineDashPattern = phase == "observe" \? \[3, 5\]/);
  assert.match(source, /: phase == "complete" \? \[18, 2\]/);
  assert.match(source, /signature\.path = coreSignaturePath\(phase, completion: completion\)/);
  assert.match(source, /case "unverified":/);
  assert.match(source, /case "cancelled":/);
  assert.match(source, /completionStyle != state\.completion/);
});
