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
  assert.match(source, /energyRing\.lineDashPattern/);
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
  assert.match(source, /kAXFocusedWindowAttribute/);
  assert.match(source, /elementSupportsCaretBounds/);
  assert.doesNotMatch(source, /fallbackComposerPoint/);
  assert.doesNotMatch(source, /focusedElementFallback/);
  assert.match(source, /private final class TypingFeedbackRenderer/);
  assert.match(source, /private func caretScreenPoint\(\) -> CGPoint\?/);
  assert.match(source, /typingRenderer\.inject\(to: reactorCenter\(\), count: count\)/);
  assert.match(source, /stageShell\.path = CGPath\(ellipseIn:/);
});
