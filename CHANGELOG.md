# Changelog

## 0.6.10 - 2026-07-21

- Kept the expanded HUD inside narrow Codex windows with a 12px safe edge.
- Added matching responsive behavior to the browser preview without shrinking the normal desktop layout.

## 0.6.9 - 2026-07-21

- Limited LOST feedback to a 3.2-second disconnect window before returning the Combo rail to READY.
- Applied the same timing to explicit failures and natural Combo expiry in browser and native overlays.

## 0.6.8 - 2026-07-21

- Treated a turn stopping while permission is still pending as an explicit cancelled completion.
- Broke Combo immediately and surfaced approval cancellation instead of returning to READY.

## 0.6.7 - 2026-07-21

- Added an explicit failed-edit lifecycle event that enters Recover without incrementing edit counts.
- Broke Combo immediately when Codex cannot apply a change instead of waiting for natural decay.

## 0.6.6 - 2026-07-21

- Prevented failed patch responses from being recorded as successful edit events.
- Kept edit counts, Momentum, and Combo free of work that Codex did not actually apply.

## 0.6.5 - 2026-07-21

- Added support for Codex freeform `apply_patch` hook input and common object aliases.
- Restored accurate edit counts and Combo continuation when patches are delivered as raw text.

## 0.6.4 - 2026-07-21

- Added lifecycle hook compatibility for Codex `exec_command` tools and their `cmd` input field.
- Routed command start, verification result, and permission events through the same semantics as the legacy `Bash` alias.

## 0.6.3 - 2026-07-20

- Gave Observe a persistent single-direction radar sweep in both browser and native macOS overlays.
- Kept the scan quieter than Act and Verify while preserving a distinct ongoing reading state.

## 0.6.2 - 2026-07-20

- Gave Act a persistent outward-propagating shard signal in both browser and native macOS overlays.
- Made ongoing action directionally opposite to Verify's inward focus instead of relying on color alone.

## 0.6.1 - 2026-07-20

- Gave Verify a persistent three-segment orbit and inward focus pulse in both browser and native macOS overlays.
- Preserved reduced-motion behavior while keeping Verify geometrically distinct from Observe and Act.

## 0.6.0 - 2026-07-20

- Integrated the redesigned reactor and telemetry frontend from `main` without losing semantic state effects.
- Added Codex-native Combo state, best-link tracking, expiry, decay, wait grace, turn/session reset, and explicit break handling.
- Added an always-visible Combo count and decay rail to both browser and native macOS overlays.
- Added coverage for hold, decay, expiry, verification failure, new-turn reset, and new-session reset.

## 0.5.8 - 2026-07-20

- Gave verified Complete a persistent three-color finish halo and check marker in both overlays.
- Kept unverified completion free of celebratory markers so the visual language remains evidence-backed.

## 0.5.7 - 2026-07-20

- Gave Recover a persistent fractured ring and repair seam in both native and browser overlays.
- Kept the recovery marker static when reduced motion is enabled.

## 0.5.6 - 2026-07-20

- Gave Wait a persistent amber breathing-gate signal around the HUD core in both native and browser overlays.
- Added an explicit preview phase query for repeatable light and dark visual acceptance checks.

## 0.5.5 - 2026-07-20

- Made the Codex `SessionStart` hook automatically ensure the native macOS overlay is running.
- Reused the existing server and native-process guards to avoid duplicate overlays across sessions.
- Added `CODEX_POWER_MODE_AUTO_NATIVE=0` for users who only want the background event service.
- Added startup-policy tests and included the session hook in syntax validation.

## 0.5.4 - 2026-07-20

- Coalesced identical rapid Observe events so consecutive reads and searches do not repeatedly restart the scan animation.
- Added a configurable Observe throttle without suppressing phase changes, edits, verification, permission, recovery, or completion events.
- Added storage-level coalescing tests to cover persistence and state accounting.

## 0.5.3 - 2026-07-20

- Added hard effect budgets for particles, shockwaves, and scan beams in both native and browser overlays.
- Tuned separate Focus and Arcade limits to prevent high-frequency Codex tool activity from causing unbounded animation buildup.

## 0.5.2 - 2026-07-17

- Increased the default HUD to a balanced 78pt and added configurable `0.75×–1.6×` scaling.

## 0.5.1 - 2026-07-17

- Reduced the native HUD from 96pt to 60pt and added a compact high-contrast status capsule.
- Added a real Momentum progress arc that remains readable over light and dark Codex themes.
- Gave Observe, Act, Verify, Wait, Recover, and Complete distinct geometry and motion.
- Replaced recovery dots with directional rectangular fragments and introduced inward verification charge.

## 0.5.0 - 2026-07-17

- Added auto-collapse and Focus/Arcade visual presets.
- Reworked the overlay into a minimal energy orb with short-lived semantic status copy.
- Added distinct scan, action, charge, attention, recovery, and verified-completion choreography.

## 0.4.0 - 2026-07-17

- Replaced line-volume combo scoring with Codex-native Momentum, Confidence, Risk, and Evidence.
- Added Observe, Act, Verify, Wait, Recover, and Complete semantic states.
- Added pre-tool and permission-request feedback.
- Redesigned the HUD as a compact transparent component floating over Codex.
- Updated the native macOS overlay for semantic states and evidence-backed completion.
- Added replay of recent local events for effect development.
- Stopped persisting verification command text.

## 0.3.0 - 2026-07-17

- Made the Codex desktop window the exclusive native Power Mode surface.
- Added automatic Codex window discovery, movement, resizing, clipping, and inactive-window hiding.
- Added virtual typing replay scaled by patch character count.
- Added shockwaves, deletion sparks, combo shake, danger borders, and stronger verification finishers.
- Removed the planned VS Code bridge from the roadmap.

## 0.2.0 - 2026-07-17

- Added a native macOS transparent, click-through overlay.
- Added multi-display and screen-edge positioning.
- Added automatic reduced-motion behavior and an explicit override.
- Added native overlay start, duplicate-process protection, and clean stop commands.
- Added macOS native compilation to continuous integration.

## 0.1.0 - 2026-07-17

- Added Codex lifecycle hooks for patch, verification, and turn completion events.
- Added local combo and verification state engine.
- Added zero-dependency real-time particle HUD.
- Added test, build, lint, and type-check command classification.
- Added verified Victory and failed-verification Danger states.
