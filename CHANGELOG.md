# Changelog

## 0.6.23 - 2026-07-21

- Grouped native diagnostics under a bilingual Status & Connection menu with separate HUD display, raw task state, last real event, task origin, following policy, and session identity rows.
- Renamed status output to `hudDisplay` and `taskState`, and added current/last event source plus last real event type to connection diagnostics.
- Suspended the browser HUD presentation timer after a settled auto-hide, with immediate wake-up on new activity, disconnect, and reconnect events.
- Kept a 100 ms cadence only while energy or Combo is visibly changing and reduced static visible states to a one-second heartbeat.
- Added an auto-hide delay setting with immediate, 2-second, and 6-second choices, so the quiet Idle orb can bridge the transition between energy settling and the HUD disappearing.
- Disabled browser caching for local HUD assets so cachebuster reinstalls and development restarts cannot leave an older visual runtime on screen.
- Replaced the ambiguous inactive-Codex visibility toggle with explicit Hide, Stay over Codex, and Follow active app policies in English and Chinese.
- Migrated the previous enabled setting to Stay over Codex, then removed the legacy boolean from newly saved configuration.
- Kept dragged and preset HUD positions inside the active display's visible area after Dock, resolution, or monitor-layout changes.
- Re-evaluated the Codex window and safe placement area immediately when macOS display parameters change, preventing removed monitors from stranding the HUD off-screen.
- Added one-shot energy tier upgrades so Charge, Flow, Surge, and Overdrive crossovers have progressively stronger Focus and Arcade beats.
- Gave Flow, Surge, and Overdrive distinct 4/8/12-node outer geometry, with a separate Overdrive ring that remains readable in Reduced Motion.
- Split successful verification into confirmation, evidence-backed reward, and new-record feedback instead of giving every passing check the same climax.
- Added a gold RECORD Combo stage and bilingual new-best copy while preserving green for ordinary evidence and dashed green for standalone confirmation.
- Added a short cyan RELINK stage when useful work resumes after natural Combo expiry, without treating a new turn or task as a continuation.
- Split the expired Combo rail and emit one restrained break impact so critical countdown, disconnect, and reconnection have distinct rhythms.
- Increased Arcade's critical cadence while keeping Focus and Reduced Motion calmer and structurally readable.
- Added event-generation guards so delayed scan echoes, repair passes, typing pulses, and chained bursts cannot leak into a newer HUD state.
- Reduced native wakeups for a fully hidden, settled HUD from four per second to one while retaining immediate 60 Hz event recovery.
- Preserved prompt-understanding semantics in Reduced Motion with a static four-way focus lock distinct from context scanning.
- Gave prompt submission a converging focus effect while preserving the horizontal scan for file and context reads.
- Added persistent completion silhouettes: a verified check, an unverified dashed warning, and a cancelled broken-ring cross.
- Turned Recover into a two-stage fracture-and-reassembly effect with converging repair fragments and visible seam stitches.
- Changed Wait from a smooth pulse into a double-beat gate alarm with paired amber attention streams.
- Reworked Verify into four evidence lanes converging on a square core with a four-corner lock silhouette.
- Gave Act a directional three-chevron silhouette and leftward rectangular drive burst so it no longer reads like Observe or Verify.
- Entered Observe immediately on `UserPromptSubmit` while deliberately discarding prompt text.
- Scoped lifecycle tracking to Codex desktop conversations so CLI and subagent activity cannot drive the HUD.
- Added session-source diagnostics to state and service health output.
- Moved the default manual runtime state to `~/.codex/power-mode` so stale demo history cannot be copied into local plugin installations.
- Preserved Codex-provided `PLUGIN_DATA` as the highest-priority storage location for installed hooks.

## 0.6.22 - 2026-07-21

- Synced streamed hook state into the active service data directory so SSE reconnects cannot fall back to stale demo or pre-install state.
- Kept event history single-sourced in the hook data directory while persisting only the already-reduced state snapshot in the service.

## 0.6.21 - 2026-07-21

- Preserved distinct static Observe, Act, Verify, Wait, Recover, and Complete markers when reduced motion is enabled.
- Removed the transient flash layer entirely in reduced-motion mode so it cannot linger as a persistent glow.

## 0.6.20 - 2026-07-21

- Paused the browser effects canvas when no particles, rings, or scans are active, then resumed it on the next Codex event.

## 0.6.19 - 2026-07-21

- Corrected the native no-change completion copy so a turn without code edits no longer recommends unnecessary verification.

## 0.6.18 - 2026-07-21

- Distinguished unverified completion with a yellow UNVERIFIED label and single verification reminder ring.
- Kept no-change completion neutral cyan while preserving green exclusively for evidence-backed completion.

## 0.6.17 - 2026-07-21

- Rendered cancelled approvals as an amber CANCELLED outcome instead of a green success-like completion.
- Added a restrained double-ring cancellation signal while reserving the green finisher for verified completion.

## 0.6.16 - 2026-07-21

- Added dedicated directional fragment feedback when Codex cannot apply an edit.
- Distinguished edit failures from verification failures with a double red impact and stronger fault shake.

## 0.6.15 - 2026-07-21

- Added explicit ONLINE and RECONNECTING feedback without replacing the six semantic Codex states.
- Kept a compact amber connection marker visible after the native HUD collapses during an outage.

## 0.6.14 - 2026-07-21

- Added capped exponential backoff when the native event stream cannot reach the service.
- Cleaned up completed sessions before reconnecting and reset the retry delay as soon as service data returns.

## 0.6.13 - 2026-07-21

- Expanded `npm run status` with service health, native PID, launch configuration, and semantic state.
- Persisted normalized native edge, scale, preset, and accessibility settings for reliable diagnostics.

## 0.6.12 - 2026-07-21

- Reduced the native overlay refresh loop from 60Hz to 4Hz while idle or holding a static Combo.
- Kept particles, semantic motion, and Combo decay at 60Hz, restoring full speed immediately when an event arrives.

## 0.6.11 - 2026-07-21

- Followed the foremost on-screen Codex window instead of selecting the largest window.
- Prevented the overlay from jumping to a larger background Codex window in multi-window workflows.

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
