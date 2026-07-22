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
